// Copyright (c) 2015 Princeton University
// All rights reserved.
// 
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above copyright
//       notice, this list of conditions and the following disclaimer in the
//       documentation and/or other materials provided with the distribution.
//     * Neither the name of Princeton University nor the
//       names of its contributors may be used to endorse or promote products
//       derived from this software without specific prior written permission.
// 
// THIS SOFTWARE IS PROVIDED BY PRINCETON UNIVERSITY "AS IS" AND
// ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL PRINCETON UNIVERSITY BE LIABLE FOR ANY
// DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
// ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

`include "define.vh"
`include "piton_system.vh"
`include "mc_define.h"
`include "chipset_define.vh"

// Filename: chipset.v
// Author: mmckeown
// Description: Top-level chipset module.  Multiplexes multiple
//              different chipset implementations and provides
//              some generic interface and bridge logic

// Macros used in this file:
//  PITON_NO_CHIP_BRIDGE        This indicates no chip bridge should be used on
//                              off chip link.  The 3 NoCs are exposed as credit
//                              based interfaces directly.  This is mainly used for FPGA
//                              where there are no pin constraints. Cannot be used with
//                              PITONSYS_INC_PASSTHRU. Note that if PITON_NO_CHIP_BRIDGE
//                              is set, io_clk is not really used.
//  PITON_CLKS_CHIPSET          indicates Piton clocks are to be generated
//                              by the chipset. Requires PITON_CHIPSET_CLKS_GEN
//  PITON_CHIPSET_DIFF_CLK      Some chipset boards use single ended clocks and some
//                              use differential clocks as input
//  PITON_CHIPSET_CLKS_GEN      If this is set, the chipset generates it own
//                              internal clocks.  Otherwise, clocks are
//                              simulated and are inputs to this module
//  PITON_FPGA_RST_ACT_HIGH     This indicates we need to invert input reset signal
//  PITONSYS_INC_PASSTHRU       Set this to include the passthrough FPGA
//                              (spartan6) for real chip Piton testing. Note
//                              this macro is not compatible with
//                              PITON_NO_CHIP_BRIDGE, as it does not make
//                              sense to have the passthru FPGA if there is no
//                              chip bridge.  The design will have compile
//                              errors if both are specified
//  PITONSYS_NO_MC              If set, no memory controller is used. This is used
//                              in the testing of the Piton system, where a small test
//                              can be run on the chip with DRAM
//                              emulated in BRAMs
//  PITON_FPGA_MC_DDR3          Set to indicate an FPGA implementation will
//                              use a DDR2/3 memory controller.  If
//                              this is not set, a default "fake"
//                              simulated DRAM is used.
//  PITONSYS_IOCTRL             Set to use real I/O controller, otherwise a fake I/O bridge 
//                              is used and emulates I/O in PLI C calls.  This may not be compatible
//                              with the "fake" memory controller or no memory controller at all
//  PITONSYS_UART               Set to include a UART in the Piton system chipset.  The UART
//                              can be used as an I/O device and/or a device for bootloading
//                              test programs (see PITONSYS_UART_BOOT)
//  PITONSYS_UART_BOOT          Set for UART boot hardware to be included.  If this is the 
//                              only boot option set, it is always used.  If there is another
//                              boot option, a switch can be used to enable UART boot
//  PITONSYS_NON_UART_BOOT      This is set whenever another boot method is specified besides UART.
//                              This is important so UART knows if it needs to be enabled or not.
//                              This is only used if PITONSYS_UART_BOOT is set
//  PITONSYS_SPI                Set to include a SPI in the Piton system chipset.  SPI is generally
//                              used for SD card boot, but could potentially be used for other
//                              purposes


module chipset(
    // Oscillator clock
`ifdef PITON_CHIPSET_CLKS_GEN
    `ifdef PITON_CHIPSET_DIFF_CLK
        input                                       clk_osc_p,
        input                                       clk_osc_n,
    `else // ifndef PITON_CHIPSET_DIFF_CLK
        input                                       clk_osc,
    `endif // endif PITON_CHIPSET_DIFF_CLK
`else // ifndef PITON_CHIPSET_CLKS_GEN
    input                                       chipset_clk,

    `ifndef PITONSYS_NO_MC
    `ifdef PITON_FPGA_MC_DDR3
        input                                       mc_clk,
    `endif // endif PITON_FPGA_MC_DDR3
    `endif // endif PITONSYS_NO_MC

    `ifdef PITONSYS_SPI
        input                                       spi_sys_clk,
    `endif // endif PITONSYS_SPI
`endif // endif PITON_CHIPSET_CLKS_GEN
    

`ifdef PITON_BOARD
    input                                       pll_lock,

    output                                      io_clk_loopback_out,
    input                                       io_clk_loopback_in,
`endif  // PITON_BOARD
    
`ifdef PITON_CLKS_CHIPSET
    // Need to generate these clocks to piton
    output                                      core_ref_clk,
    output                                      io_clk,
`else // ifndef PITON_CLKS_CHIPSET
    `ifndef PITONSYS_INC_PASSTHRU
    `ifndef PITON_NO_CHIP_BRIDGE
        input                                   io_clk,
    `endif // endif PITON_NO_CHIP_BRIDGE
    `endif // endif PITONSYS_INC_PASSTHRU
`endif // endif PITON_CLKS_CHIPSET

    // reset
    input                                       rst_n,
`ifdef PITON_BOARD
    // to chip
    output                                      chip_rst_n,
    output                                      jtag_rst_n,
    output                                      pll_rst_n,
`endif

    // Piton ready input
`ifndef PITON_BOARD
    input                                       piton_ready_n,
    output                                      chipset_prsnt_n,
`endif  // PITON_BOARD

    // There are actually 3 options for how to
    // communicate to the chip: directly without a
    // chip bridge, through the passthrough, or directly
    // with a chip bridge
`ifdef PITON_NO_CHIP_BRIDGE
    // Synchronous with core_ref_clk (same as io_clk in this case) and no virtual channels
    input                                       processor_offchip_noc1_valid,
    input  [`NOC_DATA_WIDTH-1:0]                processor_offchip_noc1_data,
    output                                      processor_offchip_noc1_yummy,
    input                                       processor_offchip_noc2_valid,
    input  [`NOC_DATA_WIDTH-1:0]                processor_offchip_noc2_data,
    output                                      processor_offchip_noc2_yummy,
    input                                       processor_offchip_noc3_valid,
    input  [`NOC_DATA_WIDTH-1:0]                processor_offchip_noc3_data,
    output                                      processor_offchip_noc3_yummy,

    output                                      offchip_processor_noc1_valid,
    output [`NOC_DATA_WIDTH-1:0]                offchip_processor_noc1_data,
    input                                       offchip_processor_noc1_yummy,
    output                                      offchip_processor_noc2_valid,
    output [`NOC_DATA_WIDTH-1:0]                offchip_processor_noc2_data,
    input                                       offchip_processor_noc2_yummy,
    output                                      offchip_processor_noc3_valid,
    output [`NOC_DATA_WIDTH-1:0]                offchip_processor_noc3_data,
    input                                       offchip_processor_noc3_yummy,
`elsif PITONSYS_INC_PASSTHRU
    // Source synchronous differential interface with virtual channels
    `ifdef PITON_CHIPSET_CLKS_GEN
        output                                      chipset_passthru_clk_p,
        output                                      chipset_passthru_clk_n,
    `else // ifndef PITON_CHIPSET_CLKS_GEN
        input                                       chipset_passthru_clk_p,
        input                                       chipset_passthru_clk_n,
    `endif // endif PITON_CHIPSET_CLKS_GEN

    input                                       passthru_chipset_clk_p,
    input                                       passthru_chipset_clk_n,

    output [31:0]                               chipset_passthru_data_p,
    output [31:0]                               chipset_passthru_data_n,
    output [1:0]                                chipset_passthru_channel_p,
    output [1:0]                                chipset_passthru_channel_n,
    input  [2:0]                                chipset_passthru_credit_back_p,
    input  [2:0]                                chipset_passthru_credit_back_n,

    input  [31:0]                               passthru_chipset_data_p,
    input  [31:0]                               passthru_chipset_data_n,
    input  [1:0]                                passthru_chipset_channel_p,
    input  [1:0]                                passthru_chipset_channel_n,
    output [2:0]                                passthru_chipset_credit_back_p,
    output [2:0]                                passthru_chipset_credit_back_n,
`else // ifndef PITON_NO_CHIP_BRIDGE && ifndef PITONSYS_INC_PASSTHRU
    // Credit interface synchronous to io_clk with virtual channels
    output [31:0]                               intf_chip_data,
    output [1:0]                                intf_chip_channel,
    input  [2:0]                                intf_chip_credit_back,

    input  [31:0]                               chip_intf_data,
    input  [1:0]                                chip_intf_channel,
    output [2:0]                                chip_intf_credit_back,
`endif // endif PITON_NO_CHIP_BRIDGE PITONSYS_INC_PASSTHRU

    // DRAM and I/O interfaces
`ifndef PITONSYS_NO_MC
`ifdef PITON_FPGA_MC_DDR3
    // Generalized interface for any FPGA board we support.
    // Not all signals will be used for all FPGA boards (see constraints)
    output [`DDR3_ADDR_WIDTH-1:0]               ddr_addr,
    output [`DDR3_BA_WIDTH-1:0]                 ddr_ba,
    output                                      ddr_cas_n,
    output [`DDR3_CK_WIDTH-1:0]                 ddr_ck_n,
    output [`DDR3_CK_WIDTH-1:0]                 ddr_ck_p,
    output [`DDR3_CKE_WIDTH-1:0]                ddr_cke,
    output                                      ddr_ras_n,
    output                                      ddr_reset_n,
    output                                      ddr_we_n,
    inout  [`DDR3_DQ_WIDTH-1:0]                 ddr_dq,
    inout  [`DDR3_DQS_WIDTH-1:0]                ddr_dqs_n,
    inout  [`DDR3_DQS_WIDTH-1:0]                ddr_dqs_p,
`ifndef NEXYSVIDEO_BOARD
    output [`DDR3_CS_WIDTH-1:0]                 ddr_cs_n,
`endif // endif NEXYSVIDEO_BOARD
    output [`DDR3_DM_WIDTH-1:0]                 ddr_dm,
    output                                      ddr_odt,
`else // ifndef PITON_FPGA_MC_DDR3
    output                                      chipset_mem_val,
    output [`NOC_DATA_WIDTH-1:0]                chipset_mem_data,
    input                                       chipset_mem_rdy,
    input                                       mem_chipset_val,
    input  [`NOC_DATA_WIDTH-1:0]                mem_chipset_data,
    output                                      mem_chipset_rdy,
`endif // endif PITON_FPGA_MC_DDR3
`endif // endif PITONSYS_NO_MC


`ifdef PITONSYS_IOCTRL
    `ifdef PITONSYS_UART
        output                                      uart_tx,
        input                                       uart_rx,
        `ifdef PITONSYS_UART_BOOT
        `ifdef PITONSYS_NON_UART_BOOT
            input                                       uart_boot_en,
            `ifndef PITONSYS_CHIPSET_TOP
                output                                      test_start,
            `endif
        `endif // endif PITONSYS_NON_UART_BOOT
        `endif // endif PITONSYS_UART_BOOT
    `endif // endif PITONSYS_UART


    `ifdef PITONSYS_SPI
        input                                       spi_data_in,
        output                                      spi_data_out,
        output                                      spi_clk_out,
        output                                      spi_cs_n,
    `endif // endif PITONSYS_SPI

`else // ifndef PITONSYS_IOCTRL
    output                                      chipset_fake_iob_val,
    output [`NOC_DATA_WIDTH-1:0]                chipset_fake_iob_data,
    input                                       chipset_fake_iob_rdy,
    input                                       fake_iob_chipset_val,
    input  [`NOC_DATA_WIDTH-1:0]                fake_iob_chipset_data,
    output                                      fake_iob_chipset_rdy,

    output                                      chipset_io_val,
    output [`NOC_DATA_WIDTH-1:0]                chipset_io_data,
    input                                       chipset_io_rdy,
    input                                       io_chipset_val,
    input  [`NOC_DATA_WIDTH-1:0]                io_chipset_data,
    output                                      io_chipset_rdy,
`endif // endif PITONSYS_IOCTRL

// Piton Board specific I/Os
`ifdef PITON_BOARD
    output [1:0]                                        sma_clk_out_p,
    output [1:0]                                        sma_clk_out_n,
    input  [1:0]                                        sma_clk_in_p,
    input  [1:0]                                        sma_clk_in_n,

    // Piton JTAG interface (requires jumpers to be enabled)
    output                                              piton_jtag_tck,
    output                                              piton_jtag_tms,
    input                                               piton_jtag_tdo,
    output                                              piton_jtag_tdi,

    // Piton power supply enable/inhibit
    output                                              asic_core_inh,
    output                                              asic_io_en,
    output                                              asic_sram_en,

    // Digital pot controlling Piton voltages control signals
    output                                              dig_pot_nrst,
    output                                              dig_pot_indep,
    output                                              dig_pot2_nrst,
    output                                              dig_pot2_indep, 

    // Uart to I2C chip control signals
    output                                              uart_i2c_rst_n,
    output                                              uart_i2c_wakeup_n,

    // UART to I2C chip GPIOs
    inout  [6:0]                                        uart_i2c_gpio,

    // BBB GPIOs
    inout  [7:0    ]                                    bbb_gpio,

    // BBB UART
    output                                              bbb_uart_tx,
    input                                               bbb_uart_rx,

    // I2C - ASIC Config, Power Monitors, BBB, UART to I2C, etc.
    input                                               i2c_scl,
    inout                                               i2c_sda,

    // Switches
    input  [15:0]                                       sw,

    // LEDs
    output [5:0]                                        leds,

    // Testpoints
    output [7:0]                                        tp,

    // Push buttons
    input  [3:0]                                        pbut,

    // Unused FMC signals
    input                                               F4_N,
    input                                               F4_P,
    input                                               F6_N,
    input                                               F6_P,
    input                                               F47_N,
    input                                               F47_P,
    input                                               F78_N,
    input                                               F78_P,
    input                                               F79_N,
    input                                               F79_P
`else   // PITON_BOARD
    `ifdef GENESYS2_BOARD
        input                                               btnl,
        input                                               btnr,
        input                                               btnu,
        input                                               btnd,

        output                                              oled_sclk,
        output                                              oled_dc,
        output                                              oled_data,
        output                                              oled_vdd_n,
        output                                              oled_vbat_n,
        output                                              oled_rst_n,
    `elsif NEXYSVIDEO_BOARD
        input                                               btnl,
        input                                               btnr,
        input                                               btnu,
        input                                               btnd,

        output                                              oled_sclk,
        output                                              oled_dc,
        output                                              oled_data,
        output                                              oled_vdd_n,
        output                                              oled_vbat_n,
        output                                              oled_rst_n,
    `endif

    output [7:0]                                        leds

`endif  // PITON_BOARD
);

///////////////////////
// Type declarations //
///////////////////////

`ifdef PITON_CLKS_CHIPSET
    wire                                        io_clk_loopback;
`endif  // PITON_CLKS_CHIPSET

// Generated clock for the core logic in the chipset
`ifdef PITON_CHIPSET_CLKS_GEN
    wire                                        chipset_clk;
    wire                                        mc_clk;
`endif // endif PITON_CHIPSET_CLKS_GEN

`ifdef PITON_BOARD
    // Internal generated clocks
    wire                                        core_ref_clk_inter;
    wire                                        core_ref_clk_inter_n;
    wire                                        io_clk_inter;
    wire                                        io_clk_inter_n;
    wire                                        passthru_chipset_clk;
    wire                                        passthru_chipset_clk_inter_n;
    wire                                        chip_rst_seq_complete_n;
    
    reg                                         passthru_fifo_init_complete;
    reg                                         rst_n_combined;
    reg                                         core_ref_clk_sync_rst_n;
    reg                                         core_ref_clk_sync_rst_n_f;
`endif

// If clk mcmm is locked
wire                                            clk_locked;

// Recitified rst_n for different rst sense on different FPGA boards
reg                                             rst_n_rect;
// Chipset reset to be used, synchronzed with chipset clk
reg                                             chipset_rst_n;
reg                                             chipset_rst_n_f;
reg                                             chipset_rst_n_ff;

// Single ended clocks for passthru communication
`ifdef PITONSYS_INC_PASSTHRU
    wire                                        chipset_passthru_clk;
    wire                                        chipset_passthru_clk_inter_n;
    wire                                        chipset_passthru_clk_oddr2_out;
    wire                                        passthru_chipset_clk;
`endif

// Intermediate val/rdy signals from fpga_bridge, not used if no chip bridge
wire  [`NOC_DATA_WIDTH-1:0]                     fpga_intf_data_noc1;
wire  [`NOC_DATA_WIDTH-1:0]                     fpga_intf_data_noc2;
wire  [`NOC_DATA_WIDTH-1:0]                     fpga_intf_data_noc3;
wire                                            fpga_intf_val_noc1;
wire                                            fpga_intf_val_noc2;
wire                                            fpga_intf_val_noc3;
wire                                            fpga_intf_rdy_noc1;
wire                                            fpga_intf_rdy_noc2;
wire                                            fpga_intf_rdy_noc3;
wire  [`NOC_DATA_WIDTH-1:0]                     intf_fpga_data_noc1;
wire  [`NOC_DATA_WIDTH-1:0]                     intf_fpga_data_noc2;
wire  [`NOC_DATA_WIDTH-1:0]                     intf_fpga_data_noc3;
wire                                            intf_fpga_val_noc1;
wire                                            intf_fpga_val_noc2;
wire                                            intf_fpga_val_noc3;
wire                                            intf_fpga_rdy_noc1;
wire                                            intf_fpga_rdy_noc2;
wire                                            intf_fpga_rdy_noc3;

`ifndef PITON_NO_CHIP_BRIDGE
// Need to convert a chip bridge interface to these if PITON_NO_CHIP_BRIDGE
// is not specified
wire                                            processor_offchip_noc1_valid;
wire  [`NOC_DATA_WIDTH-1:0]                     processor_offchip_noc1_data;
wire                                            processor_offchip_noc1_yummy;
wire                                            processor_offchip_noc2_valid;
wire  [`NOC_DATA_WIDTH-1:0]                     processor_offchip_noc2_data;
wire                                            processor_offchip_noc2_yummy;
wire                                            processor_offchip_noc3_valid;
wire  [`NOC_DATA_WIDTH-1:0]                     processor_offchip_noc3_data;
wire                                            processor_offchip_noc3_yummy;

wire                                            offchip_processor_noc1_valid;
wire  [`NOC_DATA_WIDTH-1:0]                     offchip_processor_noc1_data;
wire                                            offchip_processor_noc1_yummy;
wire                                            offchip_processor_noc2_valid;
wire  [`NOC_DATA_WIDTH-1:0]                     offchip_processor_noc2_data;
wire                                            offchip_processor_noc2_yummy;
wire                                            offchip_processor_noc3_valid;
wire  [`NOC_DATA_WIDTH-1:0]                     offchip_processor_noc3_data;
wire                                            offchip_processor_noc3_yummy;
`endif // endif PITON_NO_CHIP_BRIDGE

// Val/rdy version of aboive signals (renamed from chipset point of view)
wire  [`NOC_DATA_WIDTH-1:0]                     chipset_intf_data_noc1;
wire  [`NOC_DATA_WIDTH-1:0]                     chipset_intf_data_noc2;
wire  [`NOC_DATA_WIDTH-1:0]                     chipset_intf_data_noc3;
wire                                            chipset_intf_val_noc1;
wire                                            chipset_intf_val_noc2;
wire                                            chipset_intf_val_noc3;
wire                                            chipset_intf_rdy_noc1;
wire                                            chipset_intf_rdy_noc2;
wire                                            chipset_intf_rdy_noc3;

wire  [`NOC_DATA_WIDTH-1:0]                     intf_chipset_data_noc1;
wire  [`NOC_DATA_WIDTH-1:0]                     intf_chipset_data_noc2;
wire  [`NOC_DATA_WIDTH-1:0]                     intf_chipset_data_noc3;
wire                                            intf_chipset_val_noc1;
wire                                            intf_chipset_val_noc2;
wire                                            intf_chipset_val_noc3;
wire                                            intf_chipset_rdy_noc1;
wire                                            intf_chipset_rdy_noc2;
wire                                            intf_chipset_rdy_noc3;

`ifdef PITONSYS_INC_PASSTHRU
// Need to convert differential to these single ended signals
// if passthru is included
wire  [31:0]                                    intf_chip_data;
wire  [1:0]                                     intf_chip_channel;
wire  [2:0]                                     intf_chip_credit_back;
wire  [31:0]                                    chip_intf_data;
wire  [1:0]                                     chip_intf_channel;
wire  [2:0]                                     chip_intf_credit_back;
`endif

// Chipset DRAM initialization/calibration complete
wire                                            init_calib_complete;

wire                                            test_start;

//////////////////////
// Sequential Logic //
//////////////////////

always @ (posedge chipset_clk)
begin
    chipset_rst_n_f <= chipset_rst_n;
    chipset_rst_n_ff <= chipset_rst_n_f;
end

`ifdef PITON_BOARD
    always @(posedge core_ref_clk_inter) begin
        core_ref_clk_sync_rst_n <= rst_n_combined;
        core_ref_clk_sync_rst_n_f <= core_ref_clk_sync_rst_n;
    end

    always @(posedge passthru_chipset_clk) begin
        if (~rst_n_combined)
            passthru_fifo_init_complete <= 1'b0;
        else
            passthru_fifo_init_complete <=  fpga_intf_rdy_noc1 &
                                            fpga_intf_rdy_noc2 &
                                            fpga_intf_rdy_noc3      ? 1'b1 : passthru_fifo_init_complete;
    end
`endif  // PITON_BOARD

/////////////////////////
// Combinational Logic //
/////////////////////////

`ifndef PITON_BOARD
    `ifndef PITONSYS_INC_PASSTHRU
        assign io_clk_loopback = io_clk;
    `endif

    `ifdef PITON_CLKS_CHIPSET
        // If we are generating clocks, they are just the same as
        // this chipset clocks. This means everything is synchronous
        // to the same clock
        assign core_ref_clk     = chipset_clk;
        assign io_clk           = chipset_clk;
    `endif // PITON_CLKS_CHIPSET
`endif // PITON_BOARD

always @ *
begin
// Correct reset sense if needed
`ifdef PITON_FPGA_RST_ACT_HIGH
    rst_n_rect = ~rst_n;
`else // ifndef PITON_FPGA_RST_ACT_HIGH
    rst_n_rect = rst_n;
`endif // endif PITON_FPGA_RST_ACT_HIGH

    // Derive chipset reset
`ifdef PITON_BOARD
    chipset_rst_n = rst_n_rect & clk_locked & (~chip_rst_seq_complete_n);
`else
    chipset_rst_n = rst_n_rect & clk_locked;
`endif  // PITON_BOARD

end

`ifndef PITON_CHIPSET_CLKS_GEN
    assign clk_locked = 1'b1;
`endif // endif PITON_CHIPSET_CLKS_GEN

`ifndef PITON_BOARD
    assign chipset_prsnt_n = ~rst_n_rect | ~clk_locked | ~test_start;
`endif

`ifdef PITON_BOARD
    always @ *
    begin
        rst_n_combined = rst_n_rect & clk_locked & test_start;
    end
`endif  // PITON_BOARD


`ifdef PITON_BOARD
    assign sma_clk_out_p = 2'b00;
    assign sma_clk_out_n = 2'b00;
    assign piton_jtag_tck = 1'b0;
    assign piton_jtag_tms = 1'b0;
    assign piton_jtag_tdi = 1'b0;
    assign asic_core_inh = 1'bz;
    assign asic_io_en = 1'bz;
    assign asic_sram_en = 1'bz;
    assign dig_pot_nrst = 1'b1;
    assign dig_pot_indep = 1'b1;
    assign dig_pot2_nrst = 1'b1;
    assign dig_pot2_indep = 1'b1;
    assign uart_i2c_rst_n  = 1'b1;
    assign uart_i2c_wakeup_n = 1'b1;
    assign uart_i2c_gpio = 7'bz;
    assign bbb_gpio = 8'bz;
    assign bbb_uart_tx = 1'bz;
    assign i2c_sda = 1'bz;

    // LEDs
    assign leds[0] = clk_locked;
    assign leds[1] = chip_rst_n;
    assign leds[2] = ~chip_rst_seq_complete_n;
    assign leds[3] = passthru_fifo_init_complete;
    assign leds[4] = rst_n_combined;
    assign leds[5] = 1'b1;

    // Test points
    assign tp[7:0] = 8'd0;
`else   // PITON_BOARD
    assign leds[0] = clk_locked;
    assign leds[1] = ~piton_ready_n;
    assign leds[2] = init_calib_complete;
    assign leds[3] = processor_offchip_noc1_valid;
    assign leds[4] = processor_offchip_noc2_valid;
    assign leds[5] = offchip_processor_noc2_valid;
    assign leds[6] = offchip_processor_noc3_valid;
    `ifdef PITONSYS_IOCTRL
        `ifdef PITONSYS_UART
            `ifdef PITONSYS_UART_BOOT
                `ifdef PITONSYS_NON_UART_BOOT
                    assign leds[7] = uart_boot_en;
                `else // ifndef PITONSYS_NON_UART_BOOT
                    assign leds[7] = 1'b1;
                `endif // endif PITONSYS_NON_UART_BOOT
            `else // ifndef PITONSYS_UART_BOOT
                assign leds[7] = 1'b0;
            `endif // endif PITONSYS_UART_BOOT
        `else // ifndef PITONSYS_UART
            assign leds[7] = 1'b0;
        `endif // endif PITONSYS_UART
    `else // ifndef PITONSYS_IOCTRL
        assign leds[7] = 1'b0;
    `endif // endif PITONSYS_IOCTRL

`endif  // PITON_BOARD

//////////////////////////
// Sub-module Instances //
//////////////////////////

// Clock generation
`ifdef PITON_BOARD
    clk_dcm     clk_dcm     (
        .clk_in1_P              (clk_osc_p                      ),
        .clk_in1_N              (clk_osc_n                      ),

        .core_ref_clk           (core_ref_clk_inter             ),
        .core_ref_clk_n         (core_ref_clk_inter_n           ),
        
        .io_clk                 (io_clk_inter                   ),
        .io_clk_n               (io_clk_inter_n                 ),
        
        .passthru_chipset_clk   (passthru_chipset_clk           ),
        .passthru_chipset_clk_n (passthru_chipset_clk_inter_n   ),

        .reset                  (1'b0                           ),
        .locked                 (clk_locked                     )
    );

    assign chipset_clk = passthru_chipset_clk;
`else
    `ifdef PITON_CHIPSET_CLKS_GEN
        clk_mmcm    clk_mmcm    (
        
        `ifdef PITON_CHIPSET_DIFF_CLK
            .clk_in1_p(clk_osc_p),
            .clk_in1_n(clk_osc_n),
        `else // ifndef PITON_CHIPSET_DIFF_CLK
            .clk_in1(clk_osc),
        `endif // endif PITON_CHIPSET_DIFF_CLK

        .reset(1'b0),
        .locked(clk_locked),

        // Main chipset clock
        .chipset_clk(chipset_clk)

        `ifndef PITONSYS_NO_MC
        `ifdef PITON_FPGA_MC_DDR3
            // Memory controller clock
            , .mc_sys_clk(mc_clk)
        `endif // endif PITON_FPGA_MC_DDR3
        `endif // endif PITONSYS_NO_MC

        `ifdef PITONSYS_SPI
            // SPI system clock
            , .spi_sys_clk(spi_sys_clk)
        `endif // endif PITONSYS_SPI
        
        // Chipset<->passthru clocks
        `ifdef PITONSYS_INC_PASSTHRU
            // Chipset to passthru source synchronous clock
            , .chipset_passthru_clk(chipset_passthru_clk),
            .chipset_passthru_clk_n(chipset_passthru_clk_inter_n)
        `endif // PITONSYS_INC_PASSTHRU
    );
    `endif // endif PITON_CHIPSET_CLKS_GEN
`endif // PITON_BOARD

// If we are using a passthru, we need to convert
// differential signals to single ended
`ifdef PITONSYS_INC_PASSTHRU
    // Convert differential clocks to single ended clocks
    `ifdef PITON_CHIPSET_CLKS_GEN
        // No need to generate single ended in this case,
        // instead we need to convert single ended to differential
        // for transmission to passthru
        ODDR2 chipset_passthru_clk_oddr2(
            .CE(1'b1), .D0(1'b1), .D1(1'b0),
            .C0(chipset_passthru_clk),
            .C1(chipset_passthru_clk_inter_n),
            .Q(chipset_passthru_clk_oddr2_out)
        );
        OBUFDS chipset_passthru_clk_obufds(
            .I(chipset_passthru_clk_oddr2_out),
            .O(chipset_passthru_clk_p),
            .OB(chipset_passthru_clk_n)
        );
    `else // ifndef PITON_CHIPSET_CLKS_GEN
        // Otherwise, this chipset_passthru clk is an input to this module
        // and we need to generate the single ended from the differential
        IBUFGDS #(.DIFF_TERM("TRUE")) chipset_passthru_clk_ibufgds(
            .I(chipset_passthru_clk_p),
            .IB(chipset_passthru_clk_n),
            .O(chipset_passthru_clk)
        );
    `endif //end PITON_CHIPSET_CLKS_GEN


    IBUFGDS #(.DIFF_TERM("TRUE")) passthru_chipset_clk_ibufgds(
        .I(passthru_chipset_clk_p),
        .IB(passthru_chipset_clk_n),
        .O(passthru_chipset_clk)
    );

    // Convert differential signals to single ended
    OBUFDS chipset_passthru_data_obufds[31:0] (
        .I(intf_chip_data),
        .O(chipset_passthru_data_p),
        .OB(chipset_passthru_data_n)
    );
    OBUFDS chipset_passthru_channel_obufds[1:0] (
        .I(intf_chip_channel),
        .O(chipset_passthru_channel_p),
        .OB(chipset_passthru_channel_n)
    );
    IBUFDS  #(.DIFF_TERM("TRUE")) chipset_passthru_credit_back_ibufds[2:0] (
        .I(chipset_passthru_credit_back_p),
        .IB(chipset_passthru_credit_back_n),
        .O(intf_chip_credit_back)
    );
    IBUFDS #(.DIFF_TERM("TRUE")) passthru_chipset_data_ibufds[31:0] (
        .I(passthru_chipset_data_p),
        .IB(passthru_chipset_data_n),
        .O(chip_intf_data)
    );
    IBUFDS #(.DIFF_TERM("TRUE")) passthru_chipset_channel_ibufds[1:0] (
        .I(passthru_chipset_channel_p),
        .IB(passthru_chipset_channel_n),
        .O(chip_intf_channel)
    );
    OBUFDS passthru_chipset_credit_back_obufds[2:0] (
        .I(chip_intf_credit_back),
        .O(passthru_chipset_credit_back_p),
        .OB(passthru_chipset_credit_back_n)
    );
`endif // endif PITONSYS_INC_PASSTHRU

`ifdef PITON_BOARD
    // Output chip clocks
    ODDR2 core_ref_clk_oddr2(
        .CE(1'b1), .D0(1'b1), .D1(1'b0),
        .C0(core_ref_clk_inter),
        .C1(core_ref_clk_inter_n),
        .Q(core_ref_clk)
    );

    ODDR2 io_clk_oddr2(
        .CE(1'b1), .D0(1'b1), .D1(1'b0),
        .C0(io_clk_inter),
        .C1(io_clk_inter_n),
        .Q(io_clk)
    );

    ODDR2 io_clk_loopback_out_oddr2(
        .CE(1'b1), .D0(1'b1), .D1(1'b0),
        .C0(io_clk_inter),
        .C1(io_clk_inter_n),
        .Q(io_clk_loopback_out)
    );

    IBUFG io_clk_loopback_in_ibufg(
        .I(io_clk_loopback_in),
        .O(io_clk_loopback)
    );
`endif  // PITON_BOARD


// Convert any potential communication with chip
// to non-virtual channels credit based interface
`ifndef PITON_NO_CHIP_BRIDGE
fpga_bridge 
`ifndef PITONSYS_INC_PASSTHRU
#(.SEND_CREDIT_THRESHOLD(9'd7))
`endif // endif PITONSYS_INC_PASSTHRU
fpga_bridge(
    // This has its own internal reset synchronization
    .rst_n              (chipset_rst_n          ),
    .fpga_out_clk       (chipset_clk            ),
    .fpga_in_clk        (chipset_clk            ),

    `ifdef PITONSYS_INC_PASSTHRU
        .intf_out_clk   (chipset_passthru_clk   ),
        .intf_in_clk    (passthru_chipset_clk   ),
    `else // ifndef PITONSYS_INC_PASSTHRU
        .intf_out_clk   (io_clk_loopback        ),
        .intf_in_clk    (io_clk_loopback        ),
    `endif // endif PITONSYS_INC_PASSTHRU

    .fpga_intf_data_noc1(fpga_intf_data_noc1),
    .fpga_intf_data_noc2(fpga_intf_data_noc2),
    .fpga_intf_data_noc3(fpga_intf_data_noc3),
    .fpga_intf_val_noc1(fpga_intf_val_noc1),
    .fpga_intf_val_noc2(fpga_intf_val_noc2),
    .fpga_intf_val_noc3(fpga_intf_val_noc3),
    .fpga_intf_rdy_noc1(fpga_intf_rdy_noc1),
    .fpga_intf_rdy_noc2(fpga_intf_rdy_noc2),
    .fpga_intf_rdy_noc3(fpga_intf_rdy_noc3),

    .fpga_intf_data(intf_chip_data),
    .fpga_intf_channel(intf_chip_channel),
    .fpga_intf_credit_back(intf_chip_credit_back),

    .intf_fpga_data_noc1(intf_fpga_data_noc1),
    .intf_fpga_data_noc2(intf_fpga_data_noc2),
    .intf_fpga_data_noc3(intf_fpga_data_noc3),
    .intf_fpga_val_noc1(intf_fpga_val_noc1),
    .intf_fpga_val_noc2(intf_fpga_val_noc2),
    .intf_fpga_val_noc3(intf_fpga_val_noc3),
    .intf_fpga_rdy_noc1(intf_fpga_rdy_noc1),
    .intf_fpga_rdy_noc2(intf_fpga_rdy_noc2),
    .intf_fpga_rdy_noc3(intf_fpga_rdy_noc3),

    .intf_fpga_data(chip_intf_data),
    .intf_fpga_channel(chip_intf_channel),
    .intf_fpga_credit_back(chip_intf_credit_back)
);

// Convert from val/rdy to credit for transmission to rest of chipset
credit_to_valrdy offchip_processor_noc1_c2v(
    .clk(chipset_clk),
    .reset(~chipset_rst_n_ff),
    
    .data_in(offchip_processor_noc1_data),
    .valid_in(offchip_processor_noc1_valid),
    .yummy_in(offchip_processor_noc1_yummy),

    .data_out(fpga_intf_data_noc1),
    .valid_out(fpga_intf_val_noc1),
    .ready_out(fpga_intf_rdy_noc1)
);
credit_to_valrdy offchip_processor_noc2_c2v(
    .clk(chipset_clk),
    .reset(~chipset_rst_n_ff),
    
    .data_in(offchip_processor_noc2_data),
    .valid_in(offchip_processor_noc2_valid),
    .yummy_in(offchip_processor_noc2_yummy),

    .data_out(fpga_intf_data_noc2),
    .valid_out(fpga_intf_val_noc2),
    .ready_out(fpga_intf_rdy_noc2)
);
credit_to_valrdy offchip_processor_noc3_c2v(
    .clk(chipset_clk),
    .reset(~chipset_rst_n_ff),
    
    .data_in(offchip_processor_noc3_data),
    .valid_in(offchip_processor_noc3_valid),
    .yummy_in(offchip_processor_noc3_yummy),

    .data_out(fpga_intf_data_noc3),
    .valid_out(fpga_intf_val_noc3),
    .ready_out(fpga_intf_rdy_noc3)
);
valrdy_to_credit #(4, 3) processor_offchip_noc1_v2c(
    .clk(chipset_clk),
    .reset(~chipset_rst_n_ff),
    
    .data_in(intf_fpga_data_noc1),
    .valid_in(intf_fpga_val_noc1),
    .ready_in(intf_fpga_rdy_noc1),

    .data_out(processor_offchip_noc1_data),
    .valid_out(processor_offchip_noc1_valid),
    .yummy_out(processor_offchip_noc1_yummy)
);
valrdy_to_credit #(4, 3) processor_offchip_noc2_v2c(
    .clk(chipset_clk),
    .reset(~chipset_rst_n_ff),
    
    .data_in(intf_fpga_data_noc2),
    .valid_in(intf_fpga_val_noc2),
    .ready_in(intf_fpga_rdy_noc2),

    .data_out(processor_offchip_noc2_data),
    .valid_out(processor_offchip_noc2_valid),
    .yummy_out(processor_offchip_noc2_yummy)
);
valrdy_to_credit #(4, 3) processor_offchip_noc3_v2c(
    .clk(chipset_clk),
    .reset(~chipset_rst_n_ff),
    
    .data_in(intf_fpga_data_noc3),
    .valid_in(intf_fpga_val_noc3),
    .ready_in(intf_fpga_rdy_noc3),

    .data_out(processor_offchip_noc3_data),
    .valid_out(processor_offchip_noc3_valid),
    .yummy_out(processor_offchip_noc3_yummy)
);
`endif // endif PITON_NO_CHIP_BRIDGE

// Convert chipset val/rdy interface back to credit for transmission to fpga_bridge
valrdy_to_credit #(4, 3) offchip_processor_noc1_v2c(
    .clk(chipset_clk),
    .reset(~chipset_rst_n_ff),

    .data_in(chipset_intf_data_noc1),
    .valid_in(chipset_intf_val_noc1),
    .ready_in(chipset_intf_rdy_noc1),

    .data_out(offchip_processor_noc1_data),
    .valid_out(offchip_processor_noc1_valid),
    .yummy_out(offchip_processor_noc1_yummy)
);
valrdy_to_credit #(4, 3) offchip_processor_noc2_v2c(
    .clk(chipset_clk),
    .reset(~chipset_rst_n_ff),

    .data_in(chipset_intf_data_noc2),
    .valid_in(chipset_intf_val_noc2),
    .ready_in(chipset_intf_rdy_noc2),

    .data_out(offchip_processor_noc2_data),
    .valid_out(offchip_processor_noc2_valid),
    .yummy_out(offchip_processor_noc2_yummy)
);
valrdy_to_credit #(4, 3) offchip_processor_noc3_v2c(
    .clk(chipset_clk),
    .reset(~chipset_rst_n_ff),

    .data_in(chipset_intf_data_noc3),
    .valid_in(chipset_intf_val_noc3),
    .ready_in(chipset_intf_rdy_noc3),

    .data_out(offchip_processor_noc3_data),
    .valid_out(offchip_processor_noc3_valid),
    .yummy_out(offchip_processor_noc3_yummy)
);
credit_to_valrdy processor_offchip_noc1_c2v(
    .clk(chipset_clk),
    .reset(~chipset_rst_n_ff),
    
    .data_in(processor_offchip_noc1_data),
    .valid_in(processor_offchip_noc1_valid),
    .yummy_in(processor_offchip_noc1_yummy),

    .data_out(intf_chipset_data_noc1),
    .valid_out(intf_chipset_val_noc1),
    .ready_out(intf_chipset_rdy_noc1)
);
credit_to_valrdy processor_offchip_noc2_c2v(
    .clk(chipset_clk),
    .reset(~chipset_rst_n_ff),
    
    .data_in(processor_offchip_noc2_data),
    .valid_in(processor_offchip_noc2_valid),
    .yummy_in(processor_offchip_noc2_yummy),

    .data_out(intf_chipset_data_noc2),
    .valid_out(intf_chipset_val_noc2),
    .ready_out(intf_chipset_rdy_noc2)
);
credit_to_valrdy processor_offchip_noc3_c2v(
    .clk(chipset_clk),
    .reset(~chipset_rst_n_ff),
    
    .data_in(processor_offchip_noc3_data),
    .valid_in(processor_offchip_noc3_valid),
    .yummy_in(processor_offchip_noc3_yummy),

    .data_out(intf_chipset_data_noc3),
    .valid_out(intf_chipset_val_noc3),
    .ready_out(intf_chipset_rdy_noc3)
);

`ifdef PITON_BOARD
    // Bootup reset sequence
    chip_rst_seq rst_seq(
        .clk                (core_ref_clk_inter         ),
        .rst_n              (core_ref_clk_sync_rst_n_f  ),

        .ref_clk_locked     (clk_locked                 ),
        .chip_clk_locked    (pll_lock                   ),
        
        .pll_rst_n          (pll_rst_n                  ),
        .chip_rst_n         (chip_rst_n                 ),
        .jtag_rst_n         (jtag_rst_n                 ),
       
        .piton_ready_n      (chip_rst_seq_complete_n    )
    );
`endif  // PITON_BOARD

// Intantiate the actual chipset implementation
chipset_impl    chipset_impl    (
    .chipset_clk        (chipset_clk        ),
    .chipset_rst_n      (chipset_rst_n_ff   ),
    .piton_ready_n      (piton_ready_n      ),

    `ifndef PITONSYS_NO_MC
    `ifdef PITON_FPGA_MC_DDR3
        .mc_clk         (mc_clk             ),
    `endif // endif PITON_FPGA_MC_DDR3
    `endif // endif PITONSYS_NO_MC

    .chipset_intf_data_noc1(chipset_intf_data_noc1),
    .chipset_intf_data_noc2(chipset_intf_data_noc2),
    .chipset_intf_data_noc3(chipset_intf_data_noc3),
    .chipset_intf_val_noc1(chipset_intf_val_noc1),
    .chipset_intf_val_noc2(chipset_intf_val_noc2),
    .chipset_intf_val_noc3(chipset_intf_val_noc3),
    .chipset_intf_rdy_noc1(chipset_intf_rdy_noc1),
    .chipset_intf_rdy_noc2(chipset_intf_rdy_noc2),
    .chipset_intf_rdy_noc3(chipset_intf_rdy_noc3),

    .intf_chipset_data_noc1(intf_chipset_data_noc1),
    .intf_chipset_data_noc2(intf_chipset_data_noc2),
    .intf_chipset_data_noc3(intf_chipset_data_noc3),
    .intf_chipset_val_noc1(intf_chipset_val_noc1),
    .intf_chipset_val_noc2(intf_chipset_val_noc2),
    .intf_chipset_val_noc3(intf_chipset_val_noc3),
    .intf_chipset_rdy_noc1(intf_chipset_rdy_noc1),
    .intf_chipset_rdy_noc2(intf_chipset_rdy_noc2),
    .intf_chipset_rdy_noc3(intf_chipset_rdy_noc3)

    // DRAM and I/O interfaces
    `ifndef PITONSYS_NO_MC
        ,
        `ifdef PITON_FPGA_MC_DDR3
            .init_calib_complete(init_calib_complete),
            .ddr_addr(ddr_addr),
            .ddr_ba(ddr_ba),
            .ddr_cas_n(ddr_cas_n),
            .ddr_ck_n(ddr_ck_n),
            .ddr_ck_p(ddr_ck_p),
            .ddr_cke(ddr_cke),
            .ddr_ras_n(ddr_ras_n),
            .ddr_reset_n(ddr_reset_n),
            .ddr_we_n(ddr_we_n),
            .ddr_dq(ddr_dq),
            .ddr_dqs_n(ddr_dqs_n),
            .ddr_dqs_p(ddr_dqs_p),

            `ifndef NEXYSVIDEO_BOARD
                .ddr_cs_n(ddr_cs_n),
            `endif // endif NEXYSVIDEO_BOARD

            .ddr_dm(ddr_dm),
            .ddr_odt(ddr_odt)
        `else // ifndef PITON_FPGA_MC_DDR3
            .chipset_mem_val(chipset_mem_val),
            .chipset_mem_data(chipset_mem_data),
            .chipset_mem_rdy(chipset_mem_rdy),
            .mem_chipset_val(mem_chipset_val),
            .mem_chipset_data(mem_chipset_data),
            .mem_chipset_rdy(mem_chipset_rdy)
        `endif // endif PITON_FPGA_MC_DDR3
    `endif // endif PITONSYS_NO_MC

    `ifdef PITONSYS_IOCTRL
        `ifdef PITONSYS_UART
            ,
            .uart_tx(uart_tx),
            .uart_rx(uart_rx)
            `ifdef PITONSYS_UART_BOOT
            `ifdef PITONSYS_NON_UART_BOOT
                ,
                .uart_boot_en(uart_boot_en),
                .test_start(test_start)
            `endif // endif PITONSYS_NON_UART_BOOT
            `endif // endif PITONSYS_UART_BOOT
        `endif // endif PITONSYS_UART

        `ifdef PITONSYS_SPI
            ,
            .spi_sys_clk(spi_sys_clk),
            .spi_data_in(spi_data_in),
            .spi_clk_out(spi_clk_out),
            .spi_data_out(spi_data_out),
            .spi_cs_n(spi_cs_n)
        `endif // endif PITONSYS_SPI
    `else // ifndef PITONSYS_IOCTRL
        ,
        .chipset_fake_iob_val(chipset_fake_iob_val),
        .chipset_fake_iob_data(chipset_fake_iob_data),
        .chipset_fake_iob_rdy(chipset_fake_iob_rdy),
        .fake_iob_chipset_val(fake_iob_chipset_val),
        .fake_iob_chipset_data(fake_iob_chipset_data),
        .fake_iob_chipset_rdy(fake_iob_chipset_rdy),

        .chipset_io_val(chipset_io_val),
        .chipset_io_data(chipset_io_data),
        .chipset_io_rdy(chipset_io_rdy),
        .io_chipset_val(io_chipset_val),
        .io_chipset_data(io_chipset_data),
        .io_chipset_rdy(io_chipset_rdy)
    `endif // endif PITONSYS_IOCTRL

);


`ifdef GENESYS2_BOARD
    oled_wrapper     #(
        .OLED_SYS_CLK_KHZ   (50000),
        .OLED_SPI_CLK_KHZ   (5000)
    ) oled_wrapper (
        .sys_clk        (chipset_clk        ),
        .sys_rst_n      (chipset_rst_n_ff   ),

        .btnl           (btnl           ),
        .btnr           (btnr           ),
        .btnu           (btnu           ),
        .btnd           (btnd           ),

        .spi_sclk       (oled_sclk      ),
        .spi_dc         (oled_dc        ),
        .spi_data       (oled_data      ),
        
        .vdd_n          (oled_vdd_n     ),
        .vbat_n         (oled_vbat_n    ),
        .rst_n          (oled_rst_n     )
    );
`elsif NEXYSVIDEO_BOARD
    oled_wrapper     #(
        .OLED_SYS_CLK_KHZ   (30000),
        .OLED_SPI_CLK_KHZ   (5000)
    ) oled_wrapper (
        .sys_clk        (chipset_clk        ),
        .sys_rst_n      (chipset_rst_n_ff   ),

        .btnl           (btnl           ),
        .btnr           (btnr           ),
        .btnu           (btnu           ),
        .btnd           (btnd           ),

        .spi_sclk       (oled_sclk      ),
        .spi_dc         (oled_dc        ),
        .spi_data       (oled_data      ),
        
        .vdd_n          (oled_vdd_n     ),
        .vbat_n         (oled_vbat_n    ),
        .rst_n          (oled_rst_n     )
    );
`endif


endmodule