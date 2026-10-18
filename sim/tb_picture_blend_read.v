`timescale 1ns/1ps
module tb_picture_blend_read;
reg clk=0,rst=1,req=0,blend=0,page=0;
reg [4:0] level=16;
reg [20:0] length=512;
reg [9:0] used=0;
reg wr_busy=0,refresh=0;
wire ack,finish,clear,rd_busy,rd_en,mv;
wire [20:0] addr;
wire [31:0] data;
reg [6:0] response_valid=0;
reg [20:0] response_addr[0:6];
always #4 clk=~clk;
function [23:0] memory_pixel;
    input [20:0] address;
    integer p,n;
    begin
        p=address>=307200;n=p ? address-307200 : address;
        memory_pixel=p ? {8'd255-n[7:0],n[15:8],n[7:0]} : {n[7:0],8'd255-n[15:8],8'd255-n[7:0]};
    end
endfunction
wire [31:0] response_data={memory_pixel(response_addr[6]),8'd0};
picture_blend_read dut(.rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),
    .Sdr_init_ref_vld(refresh),.Sdr_busy(1'b0),.Sdr_rd_en(response_valid[6]),
    .Sdr_rd_dout(response_data),.App_wr_busy(wr_busy),.O_rd_busy(rd_busy),
    .App_rd_en(rd_en),.App_rd_addr(addr),.read_req(req),.read_req_ack(ack),
    .read_finish(finish),.read_addr_0(21'd0),.read_addr_1(21'd307200),
    .read_addr_2(21'd0),.read_addr_3(21'd0),.read_addr_index({1'b0,page}),
    .read_len(length),.blend_active(blend),.blend_level(level),
    .fifo_aclr(clear),.wrusedw(used),.mixed_valid(mv),.mixed_data(data));
integer i,cycle=0,written=0,commands=0,checks=0,consume_tick=0,consumed=0,pixel_phase=0,demand_delay=0;
integer expected_address,local_offset,group_size,burst_offset;
integer a,b,expected,c;
reg [23:0] oldp,newp;
reg checking=0,consume=0,pop=0;
always @(posedge clk) begin
    response_valid<={response_valid[5:0],rd_en};
    response_addr[0]<=addr;
    for(i=1;i<7;i=i+1) response_addr[i]<=response_addr[i-1];
    if(rst || clear) used<=0;
    else begin
        pop=0;
        consume_tick=(consume_tick+1)%5;
        if(consume && demand_delay<1024) demand_delay=demand_delay+1;
        if(consume && demand_delay==1024 && consume_tick==0 && consumed<length) begin
            pixel_phase=(pixel_phase+1)%800;
            if(pixel_phase<640) begin
                if(used==0) $fatal(1,"display FIFO underflow during active video");
                pop=1;
                consumed=consumed+1;
            end
        end
        case({mv,pop})
            2'b10:used<=used+1'b1;
            2'b01:used<=used-1'b1;
        endcase
        if(used>511) $fatal(1,"display FIFO overflow");
    end
end
always @(negedge clk) if(checking) begin
    cycle=cycle+1;
    // Check actual old/new page address order for every burst.
    if(rd_en) begin
        if(wr_busy || refresh) $fatal(1,"reader entered a burst while blocked");
        group_size=blend ? 256 : 128;
        local_offset=(commands/group_size)*128;
        burst_offset=commands%group_size;
        expected_address=local_offset+(burst_offset%128);
        if(blend && burst_offset<128) begin
            if(!page) expected_address=expected_address+307200;
        end else if(page) expected_address=expected_address+307200;
        if(addr!==expected_address) $fatal(1,"SDRAM address got %0d expected %0d",addr,expected_address);
        commands=commands+1;
    end
    if(mv) begin
        newp=memory_pixel(written+(page ? 307200 : 0));
        oldp=memory_pixel(written+(page ? 0 : 307200));
        for(c=0;c<3;c=c+1) begin
            a=oldp[c*8+:8];b=newp[c*8+:8];
            expected=blend ? (a*(16-level)+b*level)/16 : b;
            if(data[c*8+8+:8]!==expected[7:0])
                $fatal(1,"blend pixel %0d channel %0d level %0d got %0d expected %0d",written,c,level,data[c*8+8+:8],expected);
        end
        if(data[7:0]!==0) $fatal(1,"padding changed");
        written=written+1;
    end
end
task run;
    input on;input p;input [4:0] gain;input [20:0] words;
    begin
        repeat(15) @(negedge clk);
        blend=on;page=p;level=gain;length=words;
        written=0;commands=0;checking=1;consume=0;
        consumed=0;pixel_phase=0;demand_delay=0;
        // Backpressure before the initial burst must hold all commands.
        wr_busy=1;refresh=1;req=1;
        wait(ack);@(negedge clk);req=0;wait(!ack);
        repeat(15) @(negedge clk);
        if(commands!=0) $fatal(1,"write/refresh arbitration ignored");
        wr_busy=0;refresh=0;consume=1;
        wait(finish);repeat(10) @(negedge clk);
        if(written!=words || commands!=(on ? words*2 : words))
            $fatal(1,"blend count mismatch %0d/%0d cmds %0d",written,words,commands);
        wait(consumed==words);
        checking=0;consume=0;checks=checks+1;
    end
endtask
integer gain;
initial begin
    repeat(5) @(negedge clk);rst=0;
    run(0,0,16,512);run(0,1,16,512);
    for(gain=0;gain<=16;gain=gain+1) begin run(1,0,gain,512);run(1,1,gain,512);end
    run(1,1,8,307200);
    $display("PASS: true two-page RGB blend all 17 levels, both page directions, SDRAM burst order, FIFO backpressure and full 640x480 frame (%0d cases)",checks);
    $finish;
end
initial begin #100000000;$fatal(1,"blend reader timeout state=%0d written=%0d",dut.state,written);end
endmodule
