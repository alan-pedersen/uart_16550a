module uart_16550a_wb #(
    parameter int AW = 32,
    parameter int DW = 32
)(
    input  logic              wb_clk_i,
    input  logic              wb_rst_i,

    input  logic              wb_cyc_i,
    input  logic              wb_stb_i,
    input  logic              wb_we_i,
    input  logic [(DW/8)-1:0] wb_sel_i,
    input  logic [AW-1:0]     wb_addr_i,
    input  logic [DW-1:0]     wb_dat_i,
    output logic [DW-1:0]     wb_dat_o,
    output logic              wb_ack_o,
    output logic              wb_err_o,
    output logic              wb_rty_o,
    output logic              wb_stall_o,

    input  logic              rx,
    output logic              tx,
    output logic              irq
);
    logic       req_valid;
    logic       req_ready;
    logic       req_write;
    logic [2:0] req_addr;
    logic [7:0] req_wdata;
    logic [7:0] rsp_rdata;
    logic       rsp_valid;

    assign req_valid = wb_cyc_i && wb_stb_i && ~wb_stall_o;
    assign req_write = wb_we_i;
    assign req_addr  = wb_addr_i[2:0];
    assign req_wdata = wb_dat_i[7:0];

    uart_16550a u_uart_16550a (
        .clk       (wb_clk_i),
        .rst       (wb_rst_i),
        .req_valid (req_valid),
        .req_ready (req_ready),
        .req_write (req_write),
        .req_addr  (req_addr),
        .req_wdata (req_wdata),
        .rsp_rdata (rsp_rdata),
        .rsp_valid (rsp_valid),
        .rx        (rx),
        .tx        (tx),
        .irq       (irq)
    );

    assign wb_dat_o   = {{(DW-8){1'b0}}, rsp_rdata};
    assign wb_ack_o   = rsp_valid;
    assign wb_err_o   = 0;
    assign wb_rty_o   = 0;
    assign wb_stall_o = ~req_ready;
endmodule
