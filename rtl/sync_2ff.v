// -----------------------------------------------------------------------------
// sync_2ff.v
// Generic 2-flop synchronizer for passing a single bit (or a Gray-coded bus,
// one bit at a time is not required -- Gray code keeps a multi-bit bus safe
// to synchronize as a whole, see async_fifo.v) across a clock domain.
// -----------------------------------------------------------------------------
module sync_2ff #(
    parameter integer WIDTH = 1
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire [WIDTH-1:0]   d_in,
    output reg  [WIDTH-1:0]   d_out
);
    reg [WIDTH-1:0] stage0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage0 <= {WIDTH{1'b0}};
            d_out  <= {WIDTH{1'b0}};
        end else begin
            stage0 <= d_in;
            d_out  <= stage0;
        end
    end
endmodule
