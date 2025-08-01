# Berm_OS
My from scratch operating system project

Useful commands \n
make - builds the entire project\n
make clean - deletes the build folder, preps for rebuilding\n
./run.sh - loads main_floppy.img in qemu\n
./debug.sh - loads main_floppy.img in bochs for debugging\n

/src\n
  *contains all source files used in the actual build process, everything else is tools\n
  /bootloader\n
    *contains stage 1 and 2 of the bootloader, stage 2 in development\n
  /kernel\n
    *contains the kernel, in development\n
/build\n
  *empty in the repo, contains binary files for running\n

  Dependencies\n
  - nasm is default assembler\n
  - qemu is default for running the floppy image\n
  - bochs is default for debugging\n
  - gcc is default c compiler, not integrated yet\n
