module uart_16550a_wb #(
    parameter int AW = 32,
    parameter int DW = 32
)(
    input  logic              clk,
    input  logic              rst,

    input  logic              wb_cyc_i,
    input  logic              wb_stb_i,
    input  logic              wb_we_i,
    input  logic [(DW/8)-1:0] wb_sel_i,
    input  logic [AW-1:0]     wb_addr_i,
    input  logic [DW-1:0]     wb_dat_i,
    output logic [DW-1:0]     wb_dat_o,
    output logic              wb_ack_o,
    output logic              wb_err_o,

    input  logic              rx,
    output logic              tx,

    output logic              irq
);
    logic       csr_en;
    logic       csr_wr;
    logic [2:0] csr_addr;
    logic [7:0] csr_wdata;
    logic [7:0] csr_rdata;

    assign csr_en    = wb_valid;
    assign csr_wr    = wb.we;
    assign csr_addr  = wb.addr[2:0];
    assign csr_wdata = wb.dat_w[7:0];

    uart_16550a u_uart_16550a (
        .clk       (clk),
        .rst       (rst),
        .csr_en    (csr_en),
        .csr_wr    (csr_wr),
        .csr_addr  (csr_addr),
        .csr_wdata (csr_wdata),
        .csr_rdata (csr_rdata),
        .rx        (rx),
        .tx        (tx),
        .irq       (irq)
    );

    logic ack_q;
    logic wb_valid;

    assign wb_valid  = wb.cyc & wb.stb & ~ack_q;
    assign wb.dat_r  = {{(DW-8){1'b0}}, csr_rdata};
    assign wb.ack    = ack_q;
    assign wb.err    = 0;

    always_ff @(posedge clk) begin
        if (rst) begin
            ack_q <= 0;
        end
        else begin
            if (wb_valid) ack_q <= 1;
            else          ack_q <= 0;
        end
    end
endmodule
