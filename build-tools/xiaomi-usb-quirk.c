/* Xiaomi/MIUI USB speed correction quirk (issue #85) */
/* Xiaomi/MIUI host stacks misreport full-speed devices as low-speed. */
/* When a low-speed device reports ep0 maxpacket=64, it is actually    */
/* full-speed (low-speed maxpacket must be 8 per USB spec). Correct    */
/* the speed so the guest kernel accepts the device.                   */
if (udev->speed == USB_SPEED_LOW) {
    udev->speed = USB_SPEED_FULL;
}
