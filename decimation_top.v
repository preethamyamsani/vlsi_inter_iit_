`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Electronics Club, IIT Guwahati / Inter-IIT VLSI Challenge
// Design: Two-Stage Digital Decimation Filter Top Module
// Architecture:
//   - Stage 1: 3rd-Order CIC Decimation Filter (R=2048, N=3, M=1)
//   - Stage 2: 7-Tap Low-Latency Symmetric FIR Droop Compensator (4 Multipliers)
// Input:
//   - in_data: 2-bit signed [-1, 0, +1] bitstream bus @ Fin = 4.096 MHz
// Output:
//   - cic_data: 20-bit signed output from standalone CIC filter (Task 1)
//   - fir_data: 20-bit signed output from cascaded FIR compensator (Task 2)
//////////////////////////////////////////////////////////////////////////////////

module decimation_top #(
    parameter R         = 2048,
    parameter M         = 1,
    parameter N         = 3,
    parameter IN_WIDTH  = 2,
    parameter OUT_WIDTH = 20
)(
    input  wire                       clk,
    input  wire                       reset,
    input  wire                       enable,
    input  wire signed [IN_WIDTH-1:0] in_data,

    // Standalone CIC outputs (Task 1)
    output wire                       cic_ready,
    output wire signed [OUT_WIDTH-1:0] cic_data,

    // Cascaded FIR Compensator outputs (Task 2)
    output wire                       fir_ready,
    output wire signed [OUT_WIDTH-1:0] fir_data
);

    // =========================================================================
    // Stage 1: CIC Decimation Filter
    // =========================================================================
    cic_top #(
        .R(R),
        .M(M),
        .N(N),
        .IN_WIDTH(IN_WIDTH),
        .ACC_WIDTH(36),
        .OUT_WIDTH(OUT_WIDTH)
    ) u_cic (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .in_data(in_data),
        .outready(cic_ready),
        .out_data(cic_data)
    );

    // =========================================================================
    // Stage 2: 7-Tap FIR Droop Compensator Filter
    // =========================================================================
    fir #(
        .DATA_WIDTH(OUT_WIDTH),
        .COEFF_WIDTH(16),
        .NUM_TAPS(7),
        .Q_SHIFT(14)
    ) u_fir (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .in_ready(cic_ready),
        .in_data(cic_data),
        .outready(fir_ready),
        .out_data(fir_data)
    );

endmodule
