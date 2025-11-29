// ---------- FE <-> DE bus payload ----------
typedef struct packed {
  logic [31:0] pc;
  logic [31:0] instr;
} fe_bus_t;


module fe_de_pipe (
    input  logic clk,
    input  logic rst,

    // Fetch-side control inputs
    input  logic        stall,
    input  logic        jalr,
    input  logic        branch,
    input  logic [31:0] offset,
    input  logic [31:0] rs1_val
);
// Fetch <-> FE_DE_Skid wires
fe_bus_t fe_data_in;
logic fe_valid_in;
logic de_ready_out;

// FE_DE_Skid <-> Decode wires
fe_bus_t fe_data_out;
logic fe_valid_out;
logic de_ready_in;

fetch u_fetch (
    .clk         (clk),
    .rst         (rst),
    .stall       (stall),
    .jalr        (jalr),
    .branch      (branch),
    .offset      (offset),
    .rs1_val     (rs1_val),

    //handshake to skid
    .ready       (fe_ready_out),
    .valid       (fe_valid_in),

    // payload to skid
    .pc_decode   (fe_data_in.pc),
    .inst_decode (fe_data_in.instr)
);

// ------------ Skid Buffer (FE payload) ------------
    skid_buffer_struct #(.T(fe_bus_t)) u_skidF (
        .clk        (clk),
        .reset      (rst),

        // upstream: fetch <-> skid
        .valid_in   (fe_valid_in),
        .ready_out   (de_ready_out),
        .data_in    (fe_data_in),

        // downstream: skid <-> decode
        .valid_out  (fe_valid_out),
        .ready_in  (de_ready_in),
        .data_out   (fe_data_out)
    );
// ------------ Decode ------------
    decode u_decode_upstream (
        .clk            (clk),
        .rst            (rst),

        // upstream (from skid)
        .fe_valid       (fe_valid_out),
        .fe_instr       (fe_data_out.instr),
        .fe_pc          (fe_data_out.pc),
        .de_ready       (de_ready)      // decode advertises readiness to skid
    );

endmodule