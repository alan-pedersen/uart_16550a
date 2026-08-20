// ================================================================
// Module: uart_16550a_sync_fifo
// 
// Description:
//   Generic synchronous FIFO with configurable width and depth. The read
//   data and status signals 'empty', 'full', and 'count', are combinational
//   and reflect the active system state.

// Notes:
//   - Pushes are ignored when the FIFO is full.
//   - Pops are ignored when the FIFO is empty.
//   - DEPTH must be a power of two as wrap-around bits are used to detect
//     the 'full' condition.
// 
// Notes:
//   - The MS (Modem Status) interrupt is currently tied off (unsupported).
// ================================================================

module uart_16550a_sync_fifo #(
    parameter int WIDTH = 8,
    parameter int DEPTH = 16
)(
    input  logic                   clk,
    input  logic                   rst,
    input  logic                   push,
    input  logic                   pop,
    input  logic [WIDTH-1:0]       wdata,
    output logic [WIDTH-1:0]       rdata,
    output logic                   empty,
    output logic                   full,
    output logic [$clog2(DEPTH):0] count
);
    localparam int INDEX_BITS = $clog2(DEPTH);

    logic [WIDTH-1:0] fifo [0:DEPTH-1];

    // Pointers (+1 bit for wrap-around logic when buffer is full)
    logic [INDEX_BITS:0] rd_ptr;
    logic [INDEX_BITS:0] wr_ptr;

    assign rdata = fifo[rd_ptr[INDEX_BITS-1:0]];

    assign empty = (rd_ptr == wr_ptr);
    assign full  = ((rd_ptr[INDEX_BITS] != wr_ptr[INDEX_BITS]) &&
                    (rd_ptr[INDEX_BITS-1:0] == wr_ptr[INDEX_BITS-1:0]));

    assign count = wr_ptr - rd_ptr;

    always_ff @(posedge clk) begin
        if (rst) begin
            rd_ptr <= 0;
            wr_ptr <= 0;
        end
        else begin
            if (push && !full) begin
                fifo[wr_ptr[INDEX_BITS-1:0]] <= wdata;
                wr_ptr <= wr_ptr + 1;
            end

            if (pop && !empty) begin
                rd_ptr <= rd_ptr + 1;
            end
        end
    end
endmodule
