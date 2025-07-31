#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <ctype.h>

typedef struct {
    uint8_t BootJumpInstruction[3];
    uint8_t  OemIdentifier[8];
    uint16_t BytesPerSector;
    uint8_t  SectorsPerCluster;
    uint16_t ReservedSectors;
    uint8_t  FatCount;
    uint16_t DirEntriesCount;
    uint16_t TotalSectors;
    uint8_t  MediaDescriptorType;
    uint16_t SectorsPerFat;
    uint16_t SectorsPerTrack;
    uint16_t Heads;
    uint32_t HiddenSectors;
    uint32_t LargeSectorCount;

    // Extended Boot Record (EBR)
    uint8_t  DriveNumber;
    uint8_t  Reserved1;
    uint8_t  Signature;
    uint32_t  VolumeId;
    uint8_t  VolumeLabel[11];
    uint8_t  SystemId[8];
} __attribute__((packed)) Bootsector;

typedef struct {
    uint8_t  Name[11];           // File name (padded with spaces)
    uint8_t  Attributes;        // File attributes
    uint8_t  _Reserved;          // Reserved for Windows NT
    uint8_t  CreationTimeTenths;// Creation time (tenths of second)
    uint16_t CreatedTime;      // Creation time
    uint16_t CreatedDate;      // Creation date
    uint16_t AccessedDate;    // Last access date
    uint16_t FirstClusterHigh;  // High word of first cluster (FAT32 only, 0 for FAT12/16)
    uint16_t ModifiedTime;
    uint16_t ModifiedDate;
    uint16_t FirstClusterLow;   // Low word of first cluster
    uint32_t Size;          // File size in bytes
} __attribute__((packed)) DirectoryEntry;

Bootsector g_Bootsector;
uint8_t* g_Fat = NULL;
DirectoryEntry* g_RootDirectory = NULL;
uint32_t g_RootDirectoryEnd;


// Takes file pointer to disk image as input, reads boot sector from first sector of floppy
bool readBootSector(FILE* disk) {
    return fread(&g_Bootsector, sizeof(g_Bootsector), 1, disk) > 0;
}

// Takes file pointer to disk image, lba start num, sector count, and bufferOut mem address as input
// Reads data from specified disk at specified sector to mem at bufferOut address
bool readSectors(FILE* disk, uint32_t lba, uint32_t count, void* bufferOut) {
    bool ok = true;
    ok = ok && (fseek(disk, lba * g_Bootsector.BytesPerSector, SEEK_SET) == 0); // sets pointer to the correct address to read from
    ok = ok && (fread(bufferOut, g_Bootsector.BytesPerSector, count, disk) == count); // reads set amount of bytes into mem
    return ok;
}

bool readFat(FILE* disk) {
    g_Fat=(uint8_t*) malloc(g_Bootsector.SectorsPerFat * g_Bootsector.BytesPerSector); // allocates space for g_Fat and creates pointer to space
    return readSectors(disk, g_Bootsector.ReservedSectors, g_Bootsector.SectorsPerFat, g_Fat); // Read FAT into memory at location g_Fat
}

bool readRootDirectory(FILE* disk) {
    uint32_t lba = g_Bootsector.ReservedSectors + g_Bootsector.SectorsPerFat * g_Bootsector.FatCount; // sets lba number to after reserved sector and both FATs
    uint32_t size = sizeof(DirectoryEntry) * g_Bootsector.DirEntriesCount; // Byte size of full root directory
    uint32_t sectors = (size / g_Bootsector.BytesPerSector); // sector count of root directory
    if (size % g_Bootsector.BytesPerSector > 0) {
        sectors++; //increment to make sure there are enough sectors
    }
    g_RootDirectoryEnd = lba + sectors;
    g_RootDirectory=(DirectoryEntry*) malloc(sectors * g_Bootsector.BytesPerSector); // reserve memory for root dir and make pointer to it
    return readSectors(disk, lba, sectors, g_RootDirectory);
}

DirectoryEntry* findFile(const char* name) {
    for (uint32_t i=0; i<g_Bootsector.DirEntriesCount; i++) {
        if (memcmp(name, g_RootDirectory[i].Name, 11) == 0) {
            return &g_RootDirectory[i];
        }
    }

    return NULL;
}

bool readFile(DirectoryEntry* fileEntry, FILE* disk, uint8_t* outputBuffer) {
    bool ok = 1;
    uint16_t currentCluster = fileEntry->FirstClusterLow;

    do {
        uint32_t lba = g_RootDirectoryEnd + (currentCluster - 2) * g_Bootsector.SectorsPerCluster;
        ok = ok && readSectors(disk, lba, g_Bootsector.SectorsPerCluster, outputBuffer);
        outputBuffer += g_Bootsector.SectorsPerCluster * g_Bootsector.BytesPerSector;

        uint32_t fatIndex = currentCluster * 3 / 2;
        if (currentCluster % 2 == 0) {
            currentCluster = *(uint16_t*)(g_Fat + fatIndex) & 0x0FFF;
        } else {
            currentCluster = (*(uint16_t*)(g_Fat + fatIndex)) >> 4;
        }
    } while (ok && currentCluster < 0x0FF8);

    return ok;
}

int main(int argc, char** argv) {
    if (argc<3) {
        printf("Syntax: %s <disk image> <file name>\n",  argv[0]);
        return -1;
    }

    FILE* disk = fopen(argv[1], "rb");
    if(!disk) {
        fprintf(stderr, "Cannot open image %s!", argv[1]);
        return -1;
    }

    if (!readBootSector(disk)) {
        fprintf(stderr, "Could not read boot sector\n");
        return -2;
    }

    if (!readFat(disk)) {
        fprintf(stderr, "Could not read FAT\n");
        free(g_Fat);
        return -3;
    }
    
    if (!readRootDirectory(disk)) {
        fprintf(stderr, "Could not read root dir\n");
        free(g_Fat);
        free(g_RootDirectory);
        return -4;
    }

    DirectoryEntry* fileEntry = findFile(argv[2]);
    if (!fileEntry) {
        fprintf(stderr, "Could not find file %s\n", argv[2]);
        free(g_Fat);
        free(g_RootDirectory);
        return -5;
    }

    uint8_t* buffer = (uint8_t*) malloc(fileEntry->Size + g_Bootsector.BytesPerSector);
    if (!readFile(fileEntry, disk, buffer)) {
        fprintf(stderr, "Could not read file %s\n", argv[2]);
        free(buffer);
        free(g_Fat);
        free(g_RootDirectory);
        return -6;
    }

    for (size_t i = 0; i < fileEntry->Size; i++) {
        if (isprint(buffer[i])) {
            fputc(buffer[i], stdout);
        } else {
            printf("<%02x>", buffer[i]);
        }
    }
    printf("\n");

    free (buffer);
    free(g_Fat);
    free(g_RootDirectory);
    return 0;
}