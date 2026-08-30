/*
 * yourxdemon-agentd — TCP command-execution daemon.
 *
 * Modeled after StrykerApp's stryker-agentd: listens on a TCP port,
 * accepts one connection per command, runs it via sh -c, and streams
 * stdout+stderr back. The host Kotlin client sends a wrapped command
 * and reads until the sentinel line __EXIT__<code>.
 *
 * Protocol:
 *   1. Host connects to TCP port 9050 (SLIRP hostfwd -> guest:9050)
 *   2. Host sends a command string (shell script with PATH/HOME setup)
 *   3. Agent reads until EOF, forks, execs sh -c <command>
 *   4. stdout+stderr are dup2'd to the socket
 *   5. When sh exits, agent writes "__EXIT__<code>\n" and closes
 *
 * Build (static for Alpine):
 *   gcc -static -o yourxdemon-agentd yourxdemon-agentd.c
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <errno.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <netinet/in.h>

#define AGENT_PORT 9050
#define BACKLOG    4

static void handle_client(int client_fd) {
    /* Read the entire command from the socket (sent as one block, then EOF) */
    char cmd_buf[65536];
    size_t cmd_len = 0;
    ssize_t n;

    while (cmd_len < sizeof(cmd_buf) - 1) {
        n = read(client_fd, cmd_buf + cmd_len, sizeof(cmd_buf) - 1 - cmd_len);
        if (n <= 0) break;
        cmd_len += n;
    }
    cmd_buf[cmd_len] = '\0';

    if (cmd_len == 0) {
        close(client_fd);
        return;
    }

    /* Strip trailing newlines */
    while (cmd_len > 0 && (cmd_buf[cmd_len - 1] == '\n' || cmd_buf[cmd_len - 1] == '\r'))
        cmd_buf[--cmd_len] = '\0';

    pid_t pid = fork();
    if (pid < 0) {
        const char *err = "__EXIT__-1\n";
        write(client_fd, err, strlen(err));
        close(client_fd);
        return;
    }

    if (pid == 0) {
        /* Child: redirect stdout+stderr to the socket, exec the command */
        dup2(client_fd, STDOUT_FILENO);
        dup2(client_fd, STDERR_FILENO);
        if (client_fd > 2) close(client_fd);

        signal(SIGCHLD, SIG_DFL);
        signal(SIGHUP, SIG_DFL);

        execl("/bin/sh", "sh", "-c", cmd_buf, (char *)NULL);
        _exit(127);
    }

    /* Parent: keep socket open until child exits, then send sentinel */
    int status;
    waitpid(pid, &status, 0);

    int exit_code;
    if (WIFEXITED(status))
        exit_code = WEXITSTATUS(status);
    else if (WIFSIGNALED(status))
        exit_code = 128 + WTERMSIG(status);
    else
        exit_code = -1;

    char sentinel[64];
    int slen = snprintf(sentinel, sizeof(sentinel), "\n__EXIT__%d\n", exit_code);
    write(client_fd, sentinel, slen);

    close(client_fd);
}

static void sigchld_handler(int sig) {
    (void)sig;
    while (waitpid(-1, NULL, WNOHANG) > 0);
}

int main(int argc, char *argv[]) {
    int port = AGENT_PORT;
    if (argc > 1) port = atoi(argv[1]);
    if (port <= 0 || port > 65535) port = AGENT_PORT;

    signal(SIGCHLD, sigchld_handler);
    signal(SIGPIPE, SIG_IGN);

    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd < 0) { perror("socket"); return 1; }

    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons(port);

    if (bind(server_fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        perror("bind");
        close(server_fd);
        return 1;
    }

    if (listen(server_fd, BACKLOG) < 0) {
        perror("listen");
        close(server_fd);
        return 1;
    }

    fprintf(stderr, "[yourxdemon-agentd] listening on port %d\n", port);

    while (1) {
        int client_fd = accept(server_fd, NULL, NULL);
        if (client_fd < 0) {
            if (errno == EINTR) continue;
            perror("accept");
            continue;
        }

        pid_t child = fork();
        if (child == 0) {
            close(server_fd);
            handle_client(client_fd);
            _exit(0);
        }
        close(client_fd);
        if (child > 0)
            while (waitpid(-1, NULL, WNOHANG) > 0);
    }

    close(server_fd);
    return 0;
}
