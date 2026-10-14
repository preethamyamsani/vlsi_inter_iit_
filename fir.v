`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Electronics Club, IIT Guwahati / Inter-IIT VLSI Challenge
// Design: 7-Tap Low-Latency Symmetric FIR Droop Compensator (Stage 2)
// Architecture:
//   - Filter Length: L = 7 (Order M = 6)
//   - Group Delay: 3 samples = 1.5 ms (70% latency reduction vs 21-tap)
//   - Multipliers: Only 4 Multipliers (exploits coefficient symmetry h[k] = h[6-k])
//   - Optimization: Least Mean Squares (LMS) Inverse-Sinc Droop Compensation
//   - Arithmetic: Q14 fixed-point coefficients
//   - Input Bus: 20-bit signed from CIC filter
//   - Output Bus: Strictly 20-bit signed PCM [-524288, +524287] with outready strobe
//////////////////////////////////////////////////////////////////////////////////

module fir #(
    parameter DATA_WIDTH  = 20,
    parameter COEFF_WIDTH = 16,
    parameter NUM_TAPS    = 7,
    parameter Q_SHIFT     = 14
)(
    input  wire                         clk,
    input  wire                         reset,
    input  wire                         enable,
    input  wire                         in_ready,
    input  wire signed [DATA_WIDTH-1:0]  in_data,
    output reg                          outready,
    output reg  signed [DATA_WIDTH-1:0] out_data
);

    // =========================================================================
    // Filter Coefficients (Quantized Q14 Least-Squares Inverse-Sinc Taps)
    // h[0]..h[3], with h[6-k] = h[k]
    // =========================================================================
    localparam signed [COEFF_WIDTH-1:0] H0 = -16'sd1476;
    localparam signed [COEFF_WIDTH-1:0] H1 =  16'sd2883;
    localparam signed [COEFF_WIDTH-1:0] H2 = -16'sd7076;
    localparam signed [COEFF_WIDTH-1:0] H3 =  16'sd26656; // Center tap

    // =========================================================================
    // Pipeline Stage 1: Shift Register Delay Line (7 Taps)
    // =========================================================================
    reg signed [DATA_WIDTH-1:0] shift_reg [0:NUM_TAPS-1];
    reg in_ready_d;
    integer i;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < NUM_TAPS; i = i + 1) begin
                shift_reg[i] <= {DATA_WIDTH{1'b0}};
            end
            in_ready_d <= 1'b0;
        end else if (enable) begin
            if (in_ready) begin
                shift_reg[0] <= in_data;
                for (i = 1; i < NUM_TAPS; i = i + 1) begin
                    shift_reg[i] <= shift_reg[i-1];
                end
                in_ready_d <= 1'b1;
            end else begin
                in_ready_d <= 1'b0;
            end
        end else begin
            in_ready_d <= 1'b0;
        end
    end

    // =========================================================================
    // Pipeline Stage 2: Symmetric Pre-adders, Multipliers, & Accumulator
    // =========================================================================
    // Exploit symmetry to fold 7 taps into 4 multipliers
    wire signed [DATA_WIDTH:0]   sum0 = shift_reg[0] + shift_reg[6];
    wire signed [DATA_WIDTH:0]   sum1 = shift_reg[1] + shift_reg[5];
    wire signed [DATA_WIDTH:0]   sum2 = shift_reg[2] + shift_reg[4];
    wire signed [DATA_WIDTH-1:0] center = shift_reg[3];

    wire signed [36:0] prod0 = sum0 * H0;
    wire signed [36:0] prod1 = sum1 * H1;
    wire signed [36:0] prod2 = sum2 * H2;
    wire signed [35:0] prod3 = center * H3;

    wire signed [39:0] total_sum = prod0 + prod1 + prod2 + prod3;

    // Symmetric rounding and scaling
    wire signed [39:0] rounded_sum = total_sum + (1'b1 << (Q_SHIFT - 1));
    wire signed [39-Q_SHIFT:0] shifted_sum = rounded_sum[39:Q_SHIFT];

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            outready <= 1'b0;
            out_data <= {DATA_WIDTH{1'b0}};
        end else if (enable) begin
            if (in_ready_d) begin
                // Format and saturate strictly to 20-bit signed range [-524288, +524287]
                if (shifted_sum > 26'sd524287) begin
                    out_data <= 20'sd524287;
                end else if (shifted_sum < -26'sd524288) begin
                    out_data <= -20'sd524288;
                end else begin
                    out_data <= shifted_sum[DATA_WIDTH-1:0];
                end
                outready <= 1'b1;
            end else begin
                outready <= 1'b0;
            end
        end else begin
            outready <= 1'b0;
        end
    end

endmodule
