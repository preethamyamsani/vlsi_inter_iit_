`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Electronics Club, IIT Guwahati / Inter-IIT VLSI Challenge
// Design: Cascaded Integrator-Comb (CIC) Decimation Filter (Stage 1)
// Architecture:
//   - Filter Order: N = 3
//   - Decimation Factor: R = 2048
//   - Differential Delay: M = 1
//   - Input Bus: 2-bit signed [-1, 0, +1] matching official testbench format
//   - Internal Wordlength: 36-bit Two's-Complement wrap-around arithmetic
//     (Obeys Hogenauer bound: Bmax = 3 * log2(2048) + 2 = 35 bits)
//   - Output Bus: 20-bit signed PCM [-524288, +524287] with outready strobe
//////////////////////////////////////////////////////////////////////////////////

module cic_top #(
    parameter R         = 2048, // Decimation rate
    parameter M         = 1,    // Differential delay
    parameter N         = 3,    // Filter order
    parameter IN_WIDTH  = 2,    // Input bitwidth (2-bit signed)
    parameter ACC_WIDTH = 36,   // Internal bitwidth (>= Bmax = 35)
    parameter OUT_WIDTH = 20    // Output bitwidth
)(
    input  wire                       clk,
    input  wire                       reset,
    input  wire                       enable,
    input  wire signed [IN_WIDTH-1:0] in_data,
    output reg                        outready,
    output reg  signed [OUT_WIDTH-1:0] out_data
);

    // =========================================================================
    // 1. INTEGRATOR SECTION (Operating at oversampled clock rate Fin = 4.096 MHz)
    // =========================================================================
    reg signed [ACC_WIDTH-1:0] i1_reg;
    reg signed [ACC_WIDTH-1:0] i2_reg;
    reg signed [ACC_WIDTH-1:0] i3_reg;

    // Sign extend input to 36-bit accumulator width
    wire signed [ACC_WIDTH-1:0] in_ext = {{ (ACC_WIDTH-IN_WIDTH){in_data[IN_WIDTH-1]} }, in_data};

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            i1_reg <= {ACC_WIDTH{1'b0}};
            i2_reg <= {ACC_WIDTH{1'b0}};
            i3_reg <= {ACC_WIDTH{1'b0}};
        end else if (enable) begin
            // Pure two's-complement overflow wrap-around arithmetic
            i1_reg <= i1_reg + in_ext;
            i2_reg <= i2_reg + i1_reg + in_ext;
            i3_reg <= i3_reg + i2_reg + i1_reg + in_ext;
        end
    end

    // =========================================================================
    // 2. DECIMATION RATE SAMPLER (Subsampling by R = 2048 to Fs = 2.0 kHz)
    // =========================================================================
    reg [11:0] rate_cnt;
    reg        dec_strobe;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            rate_cnt   <= 12'd0;
            dec_strobe <= 1'b0;
        end else if (enable) begin
            if (rate_cnt == R - 1) begin
                rate_cnt   <= 12'd0;
                dec_strobe <= 1'b1;
            end else begin
                rate_cnt   <= rate_cnt + 1'b1;
                dec_strobe <= 1'b0;
            end
        end else begin
            dec_strobe <= 1'b0;
        end
    end

    // =========================================================================
    // 3. COMB / DIFFERENTIATOR SECTION (Operating at decimated clock rate Fs = 2 kHz)
    // =========================================================================
    reg signed [ACC_WIDTH-1:0] c1_d1, c1_out;
    reg signed [ACC_WIDTH-1:0] c2_d1, c2_out;
    reg signed [ACC_WIDTH-1:0] c3_d1, c3_out;
    reg dec_strobe_d1, dec_strobe_d2, dec_strobe_d3;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            c1_d1 <= {ACC_WIDTH{1'b0}};
            c1_out <= {ACC_WIDTH{1'b0}};
            dec_strobe_d1 <= 1'b0;
        end else if (enable) begin
            if (dec_strobe) begin
                c1_out <= i3_reg - c1_d1;
                c1_d1  <= i3_reg;
                dec_strobe_d1 <= 1'b1;
            end else begin
                dec_strobe_d1 <= 1'b0;
            end
        end else begin
            dec_strobe_d1 <= 1'b0;
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            c2_d1 <= {ACC_WIDTH{1'b0}};
            c2_out <= {ACC_WIDTH{1'b0}};
            dec_strobe_d2 <= 1'b0;
        end else if (enable) begin
            if (dec_strobe_d1) begin
                c2_out <= c1_out - c2_d1;
                c2_d1  <= c1_out;
                dec_strobe_d2 <= 1'b1;
            end else begin
                dec_strobe_d2 <= 1'b0;
            end
        end else begin
            dec_strobe_d2 <= 1'b0;
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            c3_d1 <= {ACC_WIDTH{1'b0}};
            c3_out <= {ACC_WIDTH{1'b0}};
            dec_strobe_d3 <= 1'b0;
        end else if (enable) begin
            if (dec_strobe_d2) begin
                c3_out <= c2_out - c3_d1;
                c3_d1  <= c2_out;
                dec_strobe_d3 <= 1'b1;
            end else begin
                dec_strobe_d3 <= 1'b0;
            end
        end else begin
            dec_strobe_d3 <= 1'b0;
        end
    end

    // =========================================================================
    // 4. OUTPUT BIT SCALING & FORMATTING (Extract MSB 20 bits)
    // =========================================================================
    // Bit scaling: Shift right by 16 bits to preserve the 20-bit dynamic range
    wire signed [ACC_WIDTH-1:0] scaled_data = c3_out >>> 16;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            outready <= 1'b0;
            out_data <= {OUT_WIDTH{1'b0}};
        end else if (enable) begin
            if (dec_strobe_d3) begin
                // Saturate strictly to 20-bit signed range [-524288, +524287]
                if (scaled_data > 36'sd524287) begin
                    out_data <= 20'sd524287;
                end else if (scaled_data < -36'sd524288) begin
                    out_data <= -20'sd524288;
                end else begin
                    out_data <= scaled_data[OUT_WIDTH-1:0];
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
