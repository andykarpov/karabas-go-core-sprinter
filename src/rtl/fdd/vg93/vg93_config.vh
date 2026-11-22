// karabas: the build configuration of the VG93 model (github.com/demyanenko-d/FD1793_1818VG93, the copy of
// karabas-go-core-profi rtl/vg93, unchanged but for VG93_SPLIT_DAL in vg93_top.v) for sp_fdd_phys (the physical
// floppy drives of the Karabas Go): SYSCLK is clk_bus (28.03 MHz), the clock of sp_fdd: one clock domain with the
// strobes of the controller, no clock from logic (as the Profi core at 28 MHz). The macros are described in vg93_top.v.
// CLK is 1 MHz (720 KB, TRD) or 2 MHz (1.44 MB) as the MAX gives it (FDD_1440). The TURBING of the MAX (CLK 2 MHz
// from a step of the head until the next read / write gate) as VG93_TURBO_STEP_IN (karabas, vg93_drive): at 1 MHz
// the step rates and head delays of 2 MHz (3 ms a step at r = 0), the read / write timing stays at 1 MHz.
`ifndef VG93_CONFIG_VH
`define VG93_CONFIG_VH
`define VG93_EMBEDDED                 // DRQ / INTRQ push-pull inside the FPGA
`define VG93_MFM_ONLY                 // DDEN_n tied low (the Sprinter writes MFM only: #FF bit 6 not used)
`define VG93_NO_TEST                  // TEST_n tied high
`define VG93_NO_RG                    // RG not used (the separator of sp_fdd_phys is free running)
`define VG93_NO_PIN33                 // /VFOE not used
`define VG93_FAST_SYSCLK              // no posedge /RAWREAD catcher (a clock from logic): the separator gives 1-SYSCLK
                                      // pulses; at 28 MHz an event moves by one SYSCLK at most (36 ns of a 1 us cell)
`define VG93_SPLIT_DAL                // karabas: DAL_I / DAL_O / DAL_OE instead of the inout DAL
`define VG93_TURBO_STEP_IN            // karabas: TURBO_STEP: the step rate of VG93_TURBO_STEP at run time
`ifndef VG93_ROM_FILE
`define VG93_ROM_FILE "rtl/fdd/vg93/vg93-microcode-rom.hex"   // from src/, as the MIF images of the ACEX
`endif
`endif
