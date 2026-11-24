// -----------------------------------------------------------------------------
// tb_async_fifo.v
// Two independent, unrelated clocks (write domain and read domain run at
// different, non-integer-related periods, deliberately, to stress the CDC
// synchronizers rather than let them get lucky with a clean ratio).
// Writes a long randomized stream, reads it back whenever the FIFO isn't
// empty, and checks: (1) data comes back in order and unmodified, (2) the
// FIFO correctly reports full when it should and never silently overwrites,
// (3) the FIFO correctly reports empty and never under-reads.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_async_fifo;

    localparam integer DATA_WIDTH = 8;
    localparam integer ADDR_WIDTH = 4;   // depth = 16
    localparam integer DEPTH      = 16;
    localparam integer NUM_WORDS  = 500;

    reg wr_clk = 0;
    reg rd_clk = 0;
    reg wr_rst_n = 0;
    reg rd_rst_n = 0;

    reg  wr_en;
    reg  [DATA_WIDTH-1:0] wr_data;
    wire full;

    reg  rd_en;
    wire [DATA_WIDTH-1:0] rd_data;
    wire empty;

    async_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .wr_clk  (wr_clk),
        .wr_rst_n(wr_rst_n),
        .wr_en   (wr_en),
        .wr_data (wr_data),
        .full    (full),

        .rd_clk  (rd_clk),
        .rd_rst_n(rd_rst_n),
        .rd_en   (rd_en),
        .rd_data (rd_data),
        .empty   (empty)
    );

    // Deliberately unrelated clock periods: write domain faster (7ns) than
    // read domain (13ns), so the FIFO will genuinely fill up and exercise
    // `full`, and the two domains never share a common edge.
    always #3.5  wr_clk = ~wr_clk;
    always #6.5  rd_clk = ~rd_clk;

    // ---------------- Write process ----------------
    reg [DATA_WIDTH-1:0] src_model [0:NUM_WORDS-1];
    integer wr_idx;
    integer wi;
    initial begin
        for (wi = 0; wi < NUM_WORDS; wi = wi + 1)
            src_model[wi] = $random;
    end

    integer write_count;
    initial begin
        wr_en   = 0;
        wr_data = 0;
        write_count = 0;
        wr_rst_n = 0;
        repeat (5) @(negedge wr_clk);
        wr_rst_n = 1;
        repeat (3) @(negedge wr_clk);

        wr_idx = 0;
        while (wr_idx < NUM_WORDS) begin
            @(negedge wr_clk);
            if (!full) begin
                wr_en   <= 1'b1;
                wr_data <= src_model[wr_idx];
                wr_idx  = wr_idx + 1;
                write_count = write_count + 1;
            end else begin
                wr_en <= 1'b0; // back off while full -- must never write when full
            end
        end
        @(negedge wr_clk);
        wr_en <= 1'b0;
    end

    // ---------------- Read process ----------------
    // rd_data is a registered output: a read issued with rd_en held during
    // the interval [T(k-1), Tk) becomes visible on rd_data starting at Tk.
    // At the TOP of this loop body (before any assignment this iteration),
    // `rd_en` still holds exactly that interval's value -- so checking
    // `rd_en` there, before updating it for the next interval, lines up
    // perfectly with what rd_data currently holds. No extra delay register
    // is needed (an earlier version added one and was off by one cycle).
    integer rd_idx;
    integer errors;
    integer full_observed;
    initial begin
        rd_en      = 0;
        rd_idx     = 0;
        errors     = 0;
        full_observed = 0;
        rd_rst_n = 0;
        repeat (5) @(negedge rd_clk);
        rd_rst_n = 1;

        while (rd_idx < NUM_WORDS) begin
            @(negedge rd_clk);
            if (full) full_observed = full_observed + 1;

            // Check the word that was issued last interval; rd_data holds it now.
            if (rd_en) begin
                if (rd_data !== src_model[rd_idx]) begin
                    $display("[FAIL] word %0d: expected 0x%02h got 0x%02h",
                              rd_idx, src_model[rd_idx], rd_data);
                    errors = errors + 1;
                end
                rd_idx = rd_idx + 1;
            end

            if (!empty) begin
                rd_en <= 1'b1;
            end else begin
                rd_en <= 1'b0;
            end
        end
        rd_en <= 1'b0;

        $display("---------------------------------------------");
        $display("Wrote %0d words, read back %0d words", write_count, rd_idx);
        $display("FIFO observed full %0d times during the run", full_observed);
        if (errors == 0 && write_count == NUM_WORDS && rd_idx == NUM_WORDS)
            $display("PASS: all %0d words crossed the async FIFO intact, in order", NUM_WORDS);
        else
            $display("FAIL: %0d data errors (wrote %0d, read %0d, expected %0d)",
                      errors, write_count, rd_idx, NUM_WORDS);
        $display("---------------------------------------------");

        if (errors != 0 || write_count != NUM_WORDS || rd_idx != NUM_WORDS)
            $fatal(1, "async_fifo testbench FAILED");

        $finish;
    end

    initial begin
        #200_000;
        $display("[TIMEOUT] watchdog fired");
        $fatal(1, "Timeout");
    end

endmodule
