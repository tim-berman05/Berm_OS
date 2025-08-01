# Berm_OS
My from scratch operating system project

Useful commands
make - builds the entire project
make clean - deletes the build folder, preps for rebuilding
./run.sh - loads main_floppy.img in qemu
./debug.sh - loads main_floppy.img in bochs for debugging

/src
  *contains all source files used in the actual build process, everything else is tools
  /bootloader
    *contains stage 1 and 2 of the bootloader, stage 2 in development
  /kernel
    *contains the kernel, in development
/build
  *empty in the repo, contains binary files for running

  Dependencies
  - nasm is default assembler
  - qemu is default for running the floppy image
  - bochs is default for debugging
  - gcc is default c compiler, not integrated yet
