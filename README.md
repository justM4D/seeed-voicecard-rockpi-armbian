# seeed-voicecard-rockpi-armbian

This is a fork of https://github.com/respeaker/seeed-voicecard to support Armbian runnong on RockPi 4b.

Requirements:
- Armbian RockPi linux version 21.05.4 (linux kernel 5.10.43-rockchip64)

Note that only the ReSpeaker Mic Hat (2-mic) is correct at this stage.

The original provides drivers for [ReSpeaker Mic Hat](https://www.seeedstudio.com/ReSpeaker-2-Mics-Pi-HAT-p-2874.html), [ReSpeaker 4 Mic Array](https://www.seeedstudio.com/ReSpeaker-4-Mic-Array-for-Raspberry-Pi-p-2941.html), [6-Mics Circular Array Kit](), and [4-Mics Linear Array Kit]() for Raspberry Pi.

Only the driver for the ReSpeaker Mic Hat has been ported correctly at this stage.

### Install seeed-voicecard
Get the seeed voice card source code and install all linux kernel drivers
```bash
git clone https://github.com/respeaker/seeed-voicecard
cd seeed-voicecard
sudo ./install_arm64.sh
sudo reboot
```

## ReSpeaker Documentation

See [Original seeed-voicecard](https://github.com/respeaker/seeed-voicecard) for additional information.
