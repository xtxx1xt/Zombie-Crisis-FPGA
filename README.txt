Project Outbreak

2-player FPGA zombie survival game for ECE 385


What this project is

Project Outbreak is a top-down zombie survival game built on an FPGA. Two players share the same screen, move around a large tile map, shoot zombies, pick up weapons and health packs, and try to survive as long as possible.


The project is split into two main parts:

* MicroBlaze software reads USB keyboard input through the MAX3421E controller
* SystemVerilog hardware runs the game logic, rendering, collision checks, and audio


Start here:

* mb_usb_hdmi_top.sv: connects all hardware modules together
* player_controller.sv: player movement, hp, camera, and weapon pickup logic
* bullet_controller.sv: bullet spawning, movement, weapon behavior, and wall collision
* zombie_manager.sv / zombie_controller.sv: zombie spawning, chasing, hp, and hit detection
* Color_Mapper.sv: tile map, sprites, UI, bullets, pickups, and final pixel color
* software/lw_usb_main.c: reads keyboard input and sends the key bitmask to hardware


Main features

Gameplay:

* two local players
* shared scrolling camera
* zombies chase the closest living player
* players can take damage, heal, and die
* kill counter and game over screen

Weapons:

* revolver: one bullet per shot
* shotgun: five short-range pellets
* uzi: automatic fire while holding the shoot key
* weapon drops are placed on the map and can be picked up by either player

World and rendering:

* 128x128 tile map
* grass, roads, fences, buildings, trees, houses, and props
* sprite ROMs and palette modules generated from image assets
* green chroma key is used as transparent color
* VGA timing is converted to HDMI output

Audio:

* PWM audio output
* short sample sounds for shooting and damage feedback


Input and controls

Player 1:

* W/A/S/D: move
* Space: shoot

Player 2:

* I/J/K/L: move
* Enter: shoot


High-level architecture

* USB keyboard input is handled in C on MicroBlaze
* the software packs key states into a 32-bit bitmask
* the bitmask is exposed to hardware through GPIO/AXI
* hardware modules update game state once per frame using vsync
* color_mapper draws the current frame from the camera position
* audio_controller plays sound effects through PWM


Hardware module summary

* mb_usb_hdmi_top.sv
  top-level module for MicroBlaze, HDMI, controllers, rendering, pickups, and audio

* player_controller.sv
  tracks player position, hp, direction, invincibility frames, camera position, and weapon state

* bullet_controller.sv
  manages 20 bullets total, with slots 0-9 for player 1 and 10-19 for player 2

* zombie_manager.sv
  owns the ten zombie slots and combines their hit masks and player damage flags

* zombie_controller.sv
  controls one zombie, including spawn, chase target, movement, hp, and bullet collision

* pickup_manager.sv
  creates health pickups after some zombie deaths and sends heal pulses on collection

* Color_Mapper.sv
  builds the map, reads sprite ROMs, handles transparency, and chooses the final RGB output

* VGA_controller.sv
  generates VGA timing for 640x480 output

* game_over_overlay.sv
  draws the end screen and final score when both players are dead

* audio_controller.sv
  reads sound samples from ROM and generates PWM audio


Software files

* software/lw_usb_main.c
  main USB polling loop and keyboard bitmask output

* software/lw_usb/MAX3421E.c
  SPI driver for the MAX3421E USB host controller

* software/lw_usb/HID.c
  keyboard HID report parsing

* software/lw_usb/project_config.h
  USB and hardware configuration constants


Build notes

* open the hardware project in Vivado
* include the generated ROM and palette modules
* generate the bitstream
* export the hardware to Vitis
* build and run the C software
* connect keyboard input through the MAX3421E USB port


Team

* Xiner Tan
* Chenxi Zhang
