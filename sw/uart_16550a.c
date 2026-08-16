/////////////// written by ai and is trash. just a simple skeleton for future ideas ////


#include "uart_16550a.h"

// === Static Helper Functions === //

static void write_reg(uart_16550a_t* dev, uint32_t offset, uint8_t val) {
    // Cast base address to volatile uint8_t pointer, add offset, and write
    *((volatile uint8_t*)(dev->base_address + offset)) = val;
}

static uint8_t read_reg(uart_16550a_t* dev, uint32_t offset) {
    return *((volatile uint8_t*)(dev->base_address + offset));
}

// === API Implementation === //

int uart_16550a_init(uart_16550a_t* dev, const uart_16550a_cfg_t* cfg) {
    if (!dev || !cfg) return -1;
    if ((cfg->data_bits < 5) || (cfg->data_bits > 8)) return -1;

    // 1. Calculate Baud Rate Divisor
    // Formula: clock / (16 * baud)
    if (cfg->baud_rate == 0 || cfg->clock_hz == 0) return -1;
    uint32_t divisor = cfg->clock_hz / (16 * cfg->baud_rate);
    if (divisor == 0 || divisor > 0xFFFF) return -1;

    // 2. Build LCR (Line Control Register) value
    uint8_t lcr = 0;
    
    // Data bits (5 bits = 0x0, 6 bits = 0x1, 7 bits = 0x2, 8 bits = 0x3)
    lcr |= (cfg->data_bits - 5); 

    // Stop bits
    switch (cfg->stop_bits) {
        case UART_STOP_BITS_ONE:      break; // 0
        case UART_STOP_BITS_ONE_HALF: 
        case UART_STOP_BITS_TWO:      lcr |= UART_16550A_LCR_STB; break;
        default: return -1;
    }

    // Parity
    switch (cfg->parity) {
        case UART_PARITY_NONE:  break;
        case UART_PARITY_ODD:   lcr |= UART_16550A_LCR_PEN; break;
        case UART_PARITY_EVEN:  lcr |= (UART_16550A_LCR_PEN | UART_16550A_LCR_EPS); break;
        case UART_PARITY_STICK: lcr |= (UART_16550A_LCR_PEN | UART_16550A_LCR_EPS | UART_16550A_LCR_SPS); break;
        default: return -1;
    }

    // 3. Set DLAB to 1 to write baud divisor
    write_reg(dev, UART_16550A_REG_LCR, UART_16550A_LCR_DLAB);
    write_reg(dev, UART_16550A_REG_DLL, (uint8_t)(divisor & 0xFF));
    write_reg(dev, UART_16550A_REG_DLM, (uint8_t)((divisor >> 8) & 0xFF));

    // 4. Clear DLAB to 0 and write normal LCR configuration
    write_reg(dev, UART_16550A_REG_LCR, lcr);

    // 5. Configure FIFOs
    if (cfg->enable_fifo) {
        // Enable FIFOs, clear both TX and RX, set RX trigger level to max (14 bytes = RXTL0 | RXTL1)
        uint8_t fcr = UART_16550A_FCR_FIFO_EN | UART_16550A_FCR_RX_RST | 
                      UART_16550A_FCR_TX_RST  | UART_16550A_FCR_RXTL0 | UART_16550A_FCR_RXTL1;
        write_reg(dev, UART_16550A_REG_FCR, fcr);
    } else {
        // Disable FIFOs
        write_reg(dev, UART_16550A_REG_FCR, 0x00);
    }

    // 6. Configure Interrupts
    if (cfg->enable_interrupts) {
        // Typically enable RX Data Available (ERBI) and Line Status (ELSI)
        write_reg(dev, UART_16550A_REG_IER, UART_16550A_IER_ERBI | UART_16550A_IER_ELSI);
    } else {
        write_reg(dev, UART_16550A_REG_IER, 0x00);
    }

    dev->initialized = true;
    return 0;
}