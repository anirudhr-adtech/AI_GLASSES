#include <memory>
#include <cstdio>
#include "verilated.h"
#include "verilated_vcd_c.h"

#ifndef TOP_HEADER
#error "Define TOP_HEADER to the Verilated header (e.g., Vtb_mac_unit.h)"
#endif

#include TOP_HEADER

double sc_time_stamp() { return 0; }

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> ctx{new VerilatedContext};
    ctx->debug(0);
    ctx->randReset(2);
    ctx->traceEverOn(true);
    ctx->commandArgs(argc, argv);

    const std::unique_ptr<TOP_CLASS> top{new TOP_CLASS{ctx.get(), "TOP"}};

    VerilatedVcdC* tfp = nullptr;
    const char* vcd_env = std::getenv("VCD_FILE");
    if (vcd_env) {
        tfp = new VerilatedVcdC;
        top->trace(tfp, 99);
        tfp->open(vcd_env);
    }

    // Initial eval at time 0 to trigger initial blocks
    ctx->time(0);
    top->eval();
    if (tfp) tfp->dump(0);

    // --timing mode event loop
    while (!ctx->gotFinish()) {
        // Check if any events remain
        if (!top->eventsPending()) break;

        // Advance to next scheduled event time
        ctx->time(top->nextTimeSlot());

        // Evaluate
        top->eval_step();
        top->eval_end_step();

        if (tfp) tfp->dump(ctx->time());
    }

    top->final();
    if (tfp) { tfp->close(); delete tfp; }
    return 0;
}
