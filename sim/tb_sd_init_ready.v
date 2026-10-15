`timescale 1ns/1ps
// Respond at the command interface. A consumer requests the first sector on
// the very first init_done edge; the request must reach CMD17, exactly once.
module tb_sd_init_ready;
reg clk=0,rst=1; always #12.5 clk=~clk;
wire init_done,cmd_req,block_req;
wire [47:0] cmd;
reg cmd_ack=0,block_ack=0;
reg read_req=0;
reg seen_init=0;
integer cmd17=0;
sd_card_sec_read_write dut(.clk(clk),.rst(rst),.sd_init_done(init_done),
    .sd_sec_read(read_req),.sd_sec_read_addr(32'h12345678),
    .sd_sec_write(1'b0),.sd_sec_write_addr(32'b0),.sd_sec_write_data(8'b0),
    .cmd_req(cmd_req),.cmd_req_ack(cmd_ack),.cmd_req_error(1'b0),.cmd(cmd),
    .block_read_req(block_req),.block_read_valid(1'b0),.block_read_data(8'b0),
    .block_read_req_ack(block_ack),.block_write_data_rd(1'b0),.block_write_req_ack(1'b0));
reg command_active=0;
always @(posedge clk) begin
    cmd_ack<=0; read_req<=0;
    if(!rst) begin
        if(init_done && !seen_init) begin read_req<=1; seen_init<=1; end
        if(cmd_req && !command_active) begin
            cmd_ack<=1; command_active<=1;
            if(cmd[47:40]==17) begin
                if(cmd[39:8]!==32'h12345678) $fatal(1,"CMD17 address mismatch");
                cmd17=cmd17+1;
            end
        end
        if(!cmd_req) command_active<=0;
        if(block_req) begin
            if(cmd17!=1) $fatal(1,"unexpected block request");
            $display("PASS: first init_done request reaches CMD17 once"); $finish;
        end
    end
end
initial begin #100 rst=0; #20000; $fatal(1,"init/read request lost"); end
endmodule
