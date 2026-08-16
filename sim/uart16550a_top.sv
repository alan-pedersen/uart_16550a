module uart_16550a_top (
    input  logic CLK100MHZ,
    input  logic CPU_RESETN,
    input  logic UART_TXD_IN,
    output logic UART_RXD_OUT
);
    import uart_16550a_pkg::*;

    localparam logic [15:0] UART_DIV_100MHZ_9600    = 16'h028B; // Works
    localparam logic [15:0] UART_DIV_100MHZ_115200  = 16'h0036; // Works
    localparam logic [15:0] UART_DIV_100MHZ_1000000 = 16'h0006; // Works
    localparam logic [15:0] UART_DIV_100MHZ_3125000 = 16'h0002; // Fails
    localparam logic [15:0] UART_DIV_100MHZ_6250000 = 16'h0001; // Fails
    localparam logic [15:0] UART_DIV_DEFAULT        = UART_DIV_100MHZ_1000000;

    typedef enum logic [3:0] {
        ST_INIT_DLAB,
        ST_INIT_DLL,
        ST_INIT_DLM,
        ST_INIT_FCR,
        ST_INIT_LCR,
        ST_READ_LSR,
        ST_CHECK_LSR,
        ST_READ_RX,
        ST_WRITE_TX
    } state_t;

    state_t     state;
    state_t     next_state;

    logic       clk;
    logic       rst;
    logic       csr_en;
    logic       csr_wr;
    logic [2:0] csr_addr;
    logic [7:0] csr_wdata;
    logic [7:0] csr_rdata;
    logic       rx;
    logic       tx;

    assign clk = CLK100MHZ;
    assign rst = ~CPU_RESETN;
    assign rx  = UART_TXD_IN;

    assign UART_RXD_OUT = tx;

    always_ff @(posedge clk) begin
        if (rst) state <= ST_INIT_DLAB;
        else     state <= next_state;
    end

    always_comb begin
        next_state = state;

        unique case (state)
            ST_INIT_DLAB: next_state = ST_INIT_DLL;
            ST_INIT_DLL:  next_state = ST_INIT_DLM;
            ST_INIT_DLM:  next_state = ST_INIT_FCR;
            ST_INIT_FCR:  next_state = ST_INIT_LCR;
            ST_INIT_LCR:  next_state = ST_READ_LSR;
            ST_READ_LSR:  next_state = ST_CHECK_LSR;
            ST_CHECK_LSR: next_state = csr_rdata[0] ? ST_READ_RX : ST_READ_LSR;
            ST_READ_RX:   next_state = ST_WRITE_TX;
            ST_WRITE_TX:  next_state = ST_READ_LSR;
        endcase
    end

    always_comb begin
        csr_en    = 0;
        csr_wr    = 0;
        csr_addr  = 0;
        csr_wdata = 0;

        unique case (state)
            ST_INIT_DLAB: begin
                csr_en    = 1;
                csr_wr    = 1;
                csr_addr  = CSR_LCR;
                csr_wdata = 8'h80;
            end
            ST_INIT_DLL: begin
                csr_en    = 1;
                csr_wr    = 1;
                csr_addr  = CSR_DLL;
                csr_wdata = UART_DIV_DEFAULT[7:0];
            end
            ST_INIT_DLM: begin
                csr_en    = 1;
                csr_wr    = 1;
                csr_addr  = CSR_DLM;
                csr_wdata = UART_DIV_DEFAULT[15:8];
            end
            ST_INIT_FCR: begin
                csr_en    = 1;
                csr_wr    = 1;
                csr_addr  = CSR_FCR;
                csr_wdata = 8'h07;
            end
            ST_INIT_LCR: begin
                csr_en    = 1;
                csr_wr    = 1;
                csr_addr  = CSR_LCR;
                csr_wdata = 8'h03;
            end
            ST_READ_LSR: begin
                csr_en   = 1;
                csr_wr   = 0;
                csr_addr = CSR_LSR;
            end
            ST_CHECK_LSR: begin
                csr_en = 0;
            end
            ST_READ_RX: begin
                csr_en   = 1;
                csr_wr   = 0;
                csr_addr = CSR_RBR;
            end
            ST_WRITE_TX: begin
                csr_en    = 1;
                csr_wr    = 1;
                csr_addr  = CSR_THR;
                csr_wdata = csr_rdata;
            end
        endcase
    end

    uart_16550a dut (
        .clk       (clk),
        .rst       (rst),
        .csr_en    (csr_en),
        .csr_wr    (csr_wr),
        .csr_addr  (csr_addr),
        .csr_wdata (csr_wdata),
        .csr_rdata (csr_rdata),
        .rx        (rx),
        .tx        (tx),
        .irq       ()
    );
endmodule
