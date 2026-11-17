from src.sec_class_define import data_desc
from sec_core.sec_core_ctrl import run_sec_core
from testbench.load_tv import read_tv_files
from testbench.checksum import checksum
from sec_dma.load_packet import load_and_dispatch_packet
from sec_top.sec_cmd_decoder.sec_cmd_decoder import cmd_decoder
from src.sec_class_define import cmd_desc_struct
from sec_top.sec_head.sec_head import gen_hdr_data
from sec_top.sec_process.sec_proc_ctrl import sec_proc_fsm


if __name__ == "__main__":
    a = 0
    # input
    i_int_start = 1
    i_enc_start = 1
    i_start = 1
    i_int_alg_id = 1 #0:null, 1:snow_3g, 2:aes, 3:zuc
    i_enc_alg_id = 1 #0:null, 1:snow_3g, 2:aes, 3:zuc


    i_sec_mode = 3 #0:enc,1:int,2:int2enc,3:enc2int
    i_count = 0x36af6144
    i_bearer = 0x1f
    i_direction = 0x0
    i_int_key = [0xf1722635, 0x58da3019, 0x44a74cf3, 0x83fd23a2]
    i_enc_key = [0x4881ff48, 0x952c4910, 0x82c5b300, 0xabd6459f]


    # width 32
    i_enc_data = [0x0d0e0f10,0x11121314,0x15161718,0x191a1b1c,0x1d1e1f20,0x21222324,0x25262728,0x292a2b2c]
    i_enc_data_vld = [1,1,1,1,1,1,1,1]
    i_enc_last     = [0,0,0,0,0,0,0,1]
    i_enc_len = 32
    #o_snow3g_enc_busy = int(0,1)
    o_cipher_data = []
    o_cipher_data_vld = []
    o_cipher_last = []
    i_int_data = [0x06070809,0x0a0b0cf6]
    i_int_data_vld = [1,1]
    i_int_last = [0,1]
    i_int_len = 8
    #o_snow3g_int_busy = int(0,1)
    o_mac_data = []
    o_mac_data_vld = []
    o_snow3g_done = 0

    i_enc_data = data_desc(i_enc_data,i_enc_data_vld,i_enc_last,i_enc_len)
    i_int_data = data_desc(i_int_data,i_int_data_vld,i_int_last,i_int_len)
    o_mac_data = data_desc([],[],[],0)
    o_cipher_data = data_desc([],[],[],0)

    #run_sec_core(i_sec_mode,i_start,i_int_alg_id,i_enc_alg_id,i_count,i_bearer,i_direction,i_int_key,i_enc_key,i_enc_data,i_int_data,o_cipher_data,o_mac_data)

    tv_path = "C:\proj\sec\script\mdm_sec\\tv\cmd_4_aes"
    tv = read_tv_files(tv_path)

    head_start = 1
    hdr_data = data_desc([],[],[],0)
    gen_hdr_data(head_start,tv.is_sdap_hdr_exit,tv.pdcp_sn_bit_size,tv.rbtype,tv.pdcp_sn,tv.sdap_hdr,hdr_data)

    cmd_desc = cmd_desc_struct()
    cmd_desc = cmd_decoder(tv.cmd,tv.packet_total_len,hdr_data.data_len,tv.maci_out_byte_offset,tv.maci_in_byte_offset,tv.cipher_in_byte_offset,tv.int_out_byte_offset,tv.int_in_byte_offset)

    pre_aad_data,proc_data,plaint_mac_data = load_and_dispatch_packet(tv.packet_total_len,tv.in_data,tv.in_data_seg_num,cmd_desc.pre_aad_len,cmd_desc.pre_aad_in_byte_offset,cmd_desc.proc_len,cmd_desc.mac_load_byte_offset,cmd_desc.mac_len,cmd_desc.mac_append,cmd_desc.mac_load_en,cmd_desc.mac_enc)

    sec_proc = sec_proc_fsm(cmd_desc.hdr_en,cmd_desc.move_en,cmd_desc.int_en,cmd_desc.enc_en,cmd_desc.sec_mode,i_error=0)
    calc_output_data,calc_mac_data = sec_proc.run_sec_proc(hdr_data,proc_data,pre_aad_data,cmd_desc.mac_append,tv.int_alg_id,tv.enc_alg_id,tv.counter,tv.bearer,tv.direction,tv.int_key,tv.cipher_key)

    checksum(calc_output_data,tv.cipher_out_byte_offset,tv.out_data,cmd_desc.mac_load_en,calc_mac_data,plaint_mac_data)


    a = 1

