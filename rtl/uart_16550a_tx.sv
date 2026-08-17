module uart_16550a_tx (
    input  logic        clk,
    input  logic        rst,
    input  logic [15:0] baud_div,
    input  logic        tx_start,
    input  logic [7:0]  tx_data,
    output logic        tx_ready,
    output logic        tx,

    input  logic [1:0]  lcr_word_len,
    input  logic        lcr_stop_bits,
    input  logic        lcr_parity_en,
    input  logic        lcr_parity_even,
    input  logic        lcr_parity_stick,
    input  logic        lcr_break_en,
    output logic        tsr_empty
);
    import uart_16550a_pkg::*;

    typedef enum logic [2:0] {
        ST_IDLE   = 3'd0,
        ST_START  = 3'd1,
        ST_DATA   = 3'd2,
        ST_PARITY = 3'd3,
        ST_STOP   = 3'd4
    } state_t;

    state_t state;

    // ================================================================
    // Baud Generation
    // ================================================================

    logic [15:0] baud_div_q;
    logic [15:0] baud_counter;
    logic        baud_tick_16x;

    // Shadow the baud divisor so DLL/DLM writes cannot
    // corrupt a transmission already in progress
    always_ff @(posedge clk) begin
        if (rst) begin
            baud_div_q <= 0;
        end
        else if (tx_ready && tx_start) begin
            baud_div_q <= baud_div;
        end
    end

    // Keep the baud counter inactive while the FSM is idle
    // or when the baud divisor is zero
    always_ff @(posedge clk) begin
        if (rst || tx_ready || (baud_div_q == 0)) begin
            baud_counter  <= 0;
            baud_tick_16x <= 0;
        end
        else if (baud_counter == (baud_div_q - 1)) begin
            baud_counter  <= 0;
            baud_tick_16x <= 1;
        end
        else begin
            baud_counter  <= baud_counter + 1;
            baud_tick_16x <= 0;
        end
    end

    // ================================================================
    // TX Control
    // ================================================================

    logic [7:0]  tsr;             // Transmit Shift Register
    logic [2:0]  max_bits;        // Number of bits per character minus 1
    logic [2:0]  bit_cnt;         // Counter to track the character bits transmitted
    logic [4:0]  stop_ticks;      // Number of baud ticks for the ST_STOP phase
    logic [4:0]  counter;         // Counter to track TX sampling ticks and ST_STOP phase ticks
    logic        parity;          // The computed parity bit
    logic        lcr_parity_en_q; // Shadowed parity enable to prevent changes mid-transaction

    always_ff @(posedge clk) begin
        if (rst) begin
            tsr             <= 0;
            max_bits        <= 0;
            bit_cnt         <= 0;
            stop_ticks      <= 0;
            counter         <= 0;
            parity          <= 0;
            lcr_parity_en_q <= 0;
            tx_ready        <= 1;
            tsr_empty       <= 1;
            state           <= ST_IDLE;
        end
        else begin
            unique case (state)
                ST_IDLE: begin
                    if (tx_ready && tx_start) begin
                        tsr             <= tx_data;
                        max_bits        <= 4 + {1'b0, lcr_word_len};
                        bit_cnt         <= 0;
                        stop_ticks      <= calc_stop_ticks(lcr_word_len, lcr_stop_bits);
                        counter         <= 0;
                        parity          <= calc_parity(tx_data, lcr_word_len, lcr_parity_even, lcr_parity_stick);
                        lcr_parity_en_q <= lcr_parity_en;
                        tx_ready        <= 0;
                        tsr_empty       <= 0;
                        state           <= ST_START;
                    end
                end
                ST_START: begin
                    if (baud_tick_16x) begin
                        if (counter == 15) begin
                            counter <= 0;
                            state   <= ST_DATA;
                        end
                        else begin
                            counter <= counter + 1;
                        end
                    end
                end
                ST_DATA: begin
                    if (baud_tick_16x) begin
                        if (counter == 15) begin
                            counter <= 0;
                            tsr     <= (tsr >> 1);
                            bit_cnt <= bit_cnt + 1;

                            if (bit_cnt == max_bits) begin
                                state <= lcr_parity_en_q ? ST_PARITY : ST_STOP;
                            end
                        end
                        else begin
                            counter <= counter + 1;
                        end
                    end
                end
                ST_PARITY: begin
                    if (baud_tick_16x) begin
                        if (counter == 15) begin
                            counter <= 0;
                            state   <= ST_STOP;
                        end
                        else begin
                            counter <= counter + 1;
                        end
                    end
                end
                ST_STOP: begin
                    if (baud_tick_16x) begin
                        if (counter == stop_ticks) begin
                            counter   <= 0;
                            tx_ready  <= 1;
                            tsr_empty <= 1;
                            state     <= ST_IDLE;
                        end
                        else begin
                            counter <= counter + 1;
                        end
                    end
                end
            endcase
        end
    end

    // ================================================================
    // TX Output
    // ================================================================

    always_ff @(posedge clk) begin
        if (rst) begin
            tx <= 1;
        end
        else if (lcr_break_en) begin
            tx <= 0;
        end
        else begin
            unique case (state)
                ST_IDLE:   tx <= 1;
                ST_START:  tx <= 0;
                ST_DATA:   tx <= tsr[0];
                ST_PARITY: tx <= parity;
                ST_STOP:   tx <= 1;
            endcase
        end
    end
endmodule
