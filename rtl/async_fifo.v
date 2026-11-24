// -----------------------------------------------------------------------------
// async_fifo.v
// Asynchronous (dual-clock) FIFO using Gray-coded read/write pointers, the
// standard Cummings-style technique for crossing a multi-bit pointer safely
// between two unrelated clock domains.
//
// Why Gray code and not binary: a 2-flop synchronizer only guarantees a
// settled, metastability-free value -- it says nothing about every BIT
// settling on the SAME cycle. A binary counter can change several bits at
// once (e.g. 0111 -> 1000), so a synchronizer sampling mid-transition can
// capture a garbage intermediate value. Gray code changes exactly one bit
// per increment, so the synchronizer can only ever see the old value or the
// new value -- never an invalid third one.
//
// Why `full`/`empty` are REGISTERED, not purely combinational: the natural
// first draft computes the next write pointer as
//   wbin_next = wbin + (wr_en && !full)
// and `full` from that same wbin_next -- which makes `full` depend on itself
// in the same timestep (full -> wbin_next -> wgray_next -> full), a
// zero-delay combinational loop that livelocks a simulator and is not
// something real synthesis hardware can resolve either. The fix (and the
// standard, Cummings-paper way to do this) is to have the pointer increment
// gate on the CURRENT, already-registered `full`, and register the new
// `full`/`empty` flags for the *next* cycle from the Gray-code comparison --
// breaking the combinational cycle at the cost of `full` being one cycle
// "pessimistic" (it reflects the state as of the last clock edge), which is
// the normal and expected behavior for this class of FIFO.
//
// Pointers are ADDR_WIDTH+1 bits wide (one bit wider than needed to address
// the memory) specifically so full and empty can be told apart: both occur
// when the lower ADDR_WIDTH bits of the write and read pointers are equal,
// and the extra MSB is what distinguishes "caught up from behind" (empty)
// from "lapped it" (full).
// -----------------------------------------------------------------------------
module async_fifo #(
    parameter integer DATA_WIDTH = 8,
    parameter integer ADDR_WIDTH = 4     // depth = 2**ADDR_WIDTH
) (
    // Write domain
    input  wire                      wr_clk,
    input  wire                      wr_rst_n,
    input  wire                      wr_en,
    input  wire [DATA_WIDTH-1:0]     wr_data,
    output reg                       full,

    // Read domain
    input  wire                      rd_clk,
    input  wire                      rd_rst_n,
    input  wire                      rd_en,
    output reg  [DATA_WIDTH-1:0]     rd_data,
    output reg                       empty
);

    localparam integer DEPTH = (1 << ADDR_WIDTH);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // ---------------- Write domain ----------------
    reg  [ADDR_WIDTH:0] wr_ptr_bin, wr_ptr_gray;
    // Gated on the CURRENT registered `full`, not a same-cycle recomputation --
    // this is what breaks the combinational loop described above.
    wire wr_fire = wr_en && !full;
    wire [ADDR_WIDTH:0] wr_ptr_bin_next  = wr_ptr_bin + wr_fire;
    wire [ADDR_WIDTH:0] wr_ptr_gray_next = (wr_ptr_bin_next >> 1) ^ wr_ptr_bin_next;

    wire [ADDR_WIDTH:0] rd_ptr_gray_sync; // read pointer, synchronized into wr_clk domain

    wire full_next = (wr_ptr_gray_next == {~rd_ptr_gray_sync[ADDR_WIDTH:ADDR_WIDTH-1],
                                             rd_ptr_gray_sync[ADDR_WIDTH-2:0]});

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_ptr_bin  <= {(ADDR_WIDTH+1){1'b0}};
            wr_ptr_gray <= {(ADDR_WIDTH+1){1'b0}};
            full        <= 1'b0;
        end else begin
            wr_ptr_bin  <= wr_ptr_bin_next;
            wr_ptr_gray <= wr_ptr_gray_next;
            full        <= full_next;
            if (wr_fire) begin
                mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= wr_data;
            end
        end
    end

    sync_2ff #(.WIDTH(ADDR_WIDTH+1)) u_sync_rd2wr (
        .clk   (wr_clk),
        .rst_n (wr_rst_n),
        .d_in  (rd_ptr_gray),
        .d_out (rd_ptr_gray_sync)
    );

    // ---------------- Read domain ----------------
    reg  [ADDR_WIDTH:0] rd_ptr_bin, rd_ptr_gray;
    wire rd_fire = rd_en && !empty;
    wire [ADDR_WIDTH:0] rd_ptr_bin_next  = rd_ptr_bin + rd_fire;
    wire [ADDR_WIDTH:0] rd_ptr_gray_next = (rd_ptr_bin_next >> 1) ^ rd_ptr_bin_next;

    wire [ADDR_WIDTH:0] wr_ptr_gray_sync; // write pointer, synchronized into rd_clk domain

    wire empty_next = (rd_ptr_gray_next == wr_ptr_gray_sync);

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_ptr_bin  <= {(ADDR_WIDTH+1){1'b0}};
            rd_ptr_gray <= {(ADDR_WIDTH+1){1'b0}};
            rd_data     <= {DATA_WIDTH{1'b0}};
            empty       <= 1'b1;
        end else begin
            rd_ptr_bin  <= rd_ptr_bin_next;
            rd_ptr_gray <= rd_ptr_gray_next;
            empty       <= empty_next;
            if (rd_fire) begin
                rd_data <= mem[rd_ptr_bin[ADDR_WIDTH-1:0]];
            end
        end
    end

    sync_2ff #(.WIDTH(ADDR_WIDTH+1)) u_sync_wr2rd (
        .clk   (rd_clk),
        .rst_n (rd_rst_n),
        .d_in  (wr_ptr_gray),
        .d_out (wr_ptr_gray_sync)
    );

endmodule
