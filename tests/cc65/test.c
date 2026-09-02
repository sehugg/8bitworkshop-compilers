/* cc65 WASI test: compiles with -t nes, links with nes.cfg + nes.lib */
#include <nes.h>

/* write a character to the PPU at address addr in nametable 0 */
static void ppu_write(unsigned addr, char c) {
    PPU.vram.address = (unsigned char)(addr >> 8);
    PPU.vram.address = (unsigned char)addr;
    PPU.vram.data = c;
}

int main(void) {
    const char *msg = "HELLO";
    unsigned i;
    ppu_write(0x2000, 'H');
    for (i = 0; msg[i] != 0; i++) {
        ppu_write(0x2001 + i, msg[i]);
    }
    while (1) ;
    return 0;
}
