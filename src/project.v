/*
 * EEG line-length seizure detector (Tiny Tapeout style top module)
 *
 * Every time `sample_valid` is high for one clock, the 8-bit EEG sample on
 * ui_in is consumed. |sample - previous_sample| is accumulated over a window of
 * 64 samples (the "line length"). At the end of each window the sum is compared
 * with THRESHOLD and the seizure flag is updated.
 *
 * Pins
 *   ui_in[7:0]   : 8-bit unsigned EEG sample
 *   uio_in[0]    : sample_valid strobe (one clock per sample)
 *   uo_out[0]    : seizure_flag (updated once per window, held until next)
 *   uo_out[1]    : window_done (1-clock pulse when a window finishes)
 *   uo_out[7:2]  : line length bits [9:4] of the last window (debug)
 */
`default_nettype none

module tt_um_eeg_linelength (
    input  wire [7:0] ui_in,    // dedicated inputs
    output wire [7:0] uo_out,   // dedicated outputs
    input  wire [7:0] uio_in,   // IOs: input path
    output wire [7:0] uio_out,  // IOs: output path
    output wire [7:0] uio_oe,   // IOs: enable path (1 = output)
    input  wire       ena,      // always 1 when powered
    input  wire       clk,
    input  wire       rst_n
);

    localparam [5:0]  WIN_LAST  = 6'd63;      // 64 samples per window
    localparam [13:0] THRESHOLD = 14'd504;    // from test/model.py

    wire sample_valid = uio_in[0];

    reg  [7:0]  prev;
    reg         have_prev;   // first sample after reset has no predecessor
    reg  [5:0]  cnt;
    reg  [13:0] acc;         // worst case 255*64 = 16320 -> 14 bits
    reg  [13:0] ll_reg;      // line length of last finished window
    reg         flag;
    reg         done;

    wire [7:0]  diff = (ui_in >= prev) ? (ui_in - prev) : (prev - ui_in);
    wire [13:0] step = have_prev ? {6'b0, diff} : 14'd0;
    wire [13:0] sum  = acc + step;

    always @(posedge clk) begin
        if (!rst_n) begin
            prev      <= 8'd0;
            have_prev <= 1'b0;
            cnt       <= 6'd0;
            acc       <= 14'd0;
            ll_reg    <= 14'd0;
            flag      <= 1'b0;
            done      <= 1'b0;
        end else begin
            done <= 1'b0;
            if (sample_valid) begin
                prev      <= ui_in;
                have_prev <= 1'b1;
                if (cnt == WIN_LAST) begin
                    ll_reg <= sum;
                    flag   <= (sum > THRESHOLD);
                    acc    <= 14'd0;
                    cnt    <= 6'd0;
                    done   <= 1'b1;
                end else begin
                    acc <= sum;
                    cnt <= cnt + 6'd1;
                end
            end
        end
    end

    assign uo_out  = {ll_reg[9:4], done, flag};
    assign uio_out = 8'd0;
    assign uio_oe  = 8'd0;   // all bidirectional pins used as inputs

    wire _unused = &{ena, uio_in[7:1], 1'b0};

endmodule
