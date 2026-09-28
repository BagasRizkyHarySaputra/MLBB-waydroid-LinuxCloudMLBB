# Disable the Waydroid virtual mouse device.
# Without this, Android InputDispatcher logs:
#   "Dropping move event because a pointer for a different device is
#    already active in display 0"
# which cancels simultaneous touch points (breaks ML joystick + skill).
device.disabled = 1
