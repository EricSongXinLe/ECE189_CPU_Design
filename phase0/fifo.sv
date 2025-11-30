//synchronous fifo: the first data wrote in will be the first to read out
//data wrote in will wrap around with one space between the start and the end

module fifo_pipeline #( 
    parameter type T = logic [31:0], 
    parameter DEPTH = 8,
    parameter FIFO_WIDTH = $clog2(DEPTH)
) ( input logic clk, 
    input logic reset, 

    input logic valid_in, 
    output logic ready_out,
    input T write_data,

    output logic valid_out, 
    input logic ready_in,
    output T read_data
);

T Arr[DEPTH-1:0];
logic [FIFO_WIDTH-1:0] w_ptr, r_ptr;
logic [FIFO_WIDTH-1:0] next_w_ptr;
logic write_en, read_en;
logic full, empty;
integer i;

assign next_w_ptr = (w_ptr==DEPTH-1)? 0 : w_ptr + 1;

assign empty = (w_ptr == r_ptr);
assign full = (next_w_ptr == r_ptr); //wrap around logic

assign valid_out = !empty;
assign ready_out = !full || (valid_out&&ready_in);

assign write_en = valid_in&&ready_out;
assign read_en = valid_out&&ready_in;

assign read_data = Arr[r_ptr];

always_ff @ (posedge clk) begin
    if (reset) begin
        for (i = 0; i<DEPTH; i=i+1) begin
            Arr[i] <= '0;
    end
    w_ptr <= '0;
    r_ptr <= '0;
    end

    if (read_en && (!empty)) begin
        r_ptr <= (r_ptr==DEPTH-1)? 0 : r_ptr + 1;
    end
    if (write_en && (!full || read_en)) begin // ||read_en: to prevent read and write happen the same cycle
        Arr[w_ptr] <= write_data;
        w_ptr <= (w_ptr==DEPTH-1)? 0 : w_ptr + 1;

    end
end
endmodule

module fifo #( 
    parameter type T = logic [31:0], 
    parameter DEPTH = 8 
) ( input logic clk, 
    input logic reset, 
    input logic write_en, 
    input T write_data,
    input logic read_en, 
    output T read_data, 
    output logic full, 
    output logic empty);

T Arr[DEPTH-1:0];
logic [2:0] w_ptr, r_ptr;
integer i;

assign empty = (w_ptr == r_ptr);
assign full = ((w_ptr + 3'd1) == r_ptr); //wrap around logic

always_ff @ (posedge clk) begin
    if (reset) begin
        for (i = 0; i<DEPTH; i=i+1) begin
            Arr[i] <= '0;
    end
    w_ptr <= '0;
    r_ptr <= '0;
    read_data <= '0;
    end

    if (read_en && (!empty)) begin
        read_data <= Arr[r_ptr];
        r_ptr <= r_ptr + 1;
    end
    if (write_en && (!full || read_en)) begin // ||read_en: to prevent read and write happen the same cycle
        Arr[w_ptr] <= write_data;
        w_ptr <= w_ptr + 1;

    end
end
endmodule


//circular buffer: alteration from FIFO: new data always get stored, even if it overwrites the old data (implemented before clarification)
module c_buffer #( 
    parameter type T = logic [31:0], 
    parameter DEPTH = 8 
) ( input logic clk, 
    input logic reset, 
    input logic write_en, 
    input T write_data,
    input logic read_en, 
    output T read_data, 
    output logic full, 
    output logic empty);

T Arr[DEPTH-1:0];
logic [2:0] w_ptr, r_ptr;
integer i;

assign empty = (w_ptr == r_ptr);
assign full = ((w_ptr + 3'd1) == r_ptr);

always_ff @ (posedge clk) begin
    if (reset) begin
        for (i = 0; i<DEPTH; i=i+1) begin
            Arr[i] <= '0;
    end
    w_ptr <= '0;
    r_ptr <= '0;
    read_data <= '0;
    end

    else begin
        if (read_en && (!empty)) begin
            read_data <= Arr[r_ptr];
            r_ptr <= r_ptr + 1;
        end
        if (write_en && (!full || read_en)) begin
            Arr[w_ptr] <= write_data;
            w_ptr <= w_ptr + 1;
        end
        if (write_en && full && !read_en) begin
            $display ("detect overflow; oldest data discarded");
            Arr[w_ptr] <= write_data;
            w_ptr <= w_ptr + 1;
            r_ptr <= r_ptr + 1;
        end
    end
end
endmodule
