from src.sec_class_define import data_desc
from src.sec_fifo import sec_fifo
# 数据进2路，int(only int, it can use), pre_aad, proc, hdr, calc_mac, cipher;  出4路 move, int, enc, maci
# 每路数据开头都是对齐的，需要对结尾数据进行拼接, 使用sec_fifo
# move 去做enc, 加密为NULL
def pop_word_from_data_desc(data:data_desc):
    pop_bytes = 4
    mac = data_desc([],[],[],0)
    if data.data_len < pop_bytes:
        return False
    top_bytes = (data.data_len-1) % 4 + 1
    rem = pop_bytes - top_bytes
    top_data = data.data.pop()
    #bytes.append(top_data)
    data.data_vld.pop()
    data.last.pop(2)
    data.last.append(1)
    data.data_len -= pop_bytes
    if rem == 0:
        mac.data.append(top_data)
    elif rem == 1:
        sec_top_data = data.data.pop()
        mac.data.append(sec_top_data & 0xFF + top_data)
        data.data.append(sec_top_data & 0xFFFFFF00)
    elif rem == 2:
        sec_top_data = data.data.pop()
        mac.data.append(sec_top_data & 0xFFFF + top_data)
        data.data.append(sec_top_data & 0xFFFF0000)
    elif rem == 3:
        sec_top_data = data.data.pop()
        mac.data.append(sec_top_data & 0xFFFFFF + top_data)
        data.data.append(sec_top_data & 0xFF000000)
    mac.data_len = 4
    mac.last.append(1)
    mac.data_vld.append(1)
    return mac

def sec_recomb_data_stage1(i_sec_proc_state,i_head_data,i_proc_data,i_pre_aad_data):
    a = 0
    int_sec_fifo = sec_fifo(64)
    enc_sec_fifo = sec_fifo(64)
    int_data_list = []
    enc_data_list = []
    no_enc = 0
    dec_mac_data = data_desc([],[],[],0)
    if i_sec_proc_state == "HEAD":
        enc_data_list.append(i_head_data)
    elif i_sec_proc_state == "MOVE":
        enc_data_list.append(i_proc_data)
        no_enc = 1
    elif i_sec_proc_state == "INT_MOVE":
        int_data_list.append(i_pre_aad_data)
        int_data_list.append(i_proc_data)
    elif i_sec_proc_state == "INT":
        int_data_list.append(i_pre_aad_data)
        int_data_list.append(i_proc_data)
    elif i_sec_proc_state == "ENC":
        enc_data_list.append(i_proc_data)
    elif i_sec_proc_state == "INT2ENC":
        int_data_list.append(i_pre_aad_data)
        int_data_list.append(i_proc_data)
    elif i_sec_proc_state == "ENC2INT":
        # TODO 注意 此时的mac 也需要放到 outfifo中
        enc_data_list.append(i_proc_data)

    int_seg_num = len(int_data_list)
    int_total_seg_bytes = []
    for i in range(int_seg_num):
        seg_bytes += int_data_list[i].data_len
    int_total_seg_bytes.append(seg_bytes)
    int_data = int_sec_fifo.run(int_data_list,int_seg_num,0.02,int_total_seg_bytes,1,False,0.05)

    enc_seg_num = len(enc_data_list)
    enc_total_seg_bytes = []
    for i in range(enc_seg_num):
        seg_bytes += enc_data_list[i].data_len
    enc_total_seg_bytes.append(seg_bytes)
    enc_data = enc_sec_fifo.run(enc_data_list,enc_seg_num,0.02,enc_total_seg_bytes,1,False,0.05)
    return int_data,enc_data


def sec_recomb_data_stage2(i_sec_proc_state,i_int_done,i_mac_append,i_proc_data,i_pre_aad_data,i_mac_clac_data,i_cipher_data):
    int_sec_fifo = sec_fifo(64)
    enc_sec_fifo = sec_fifo(64)
    int_data_list = []
    enc_data_list = []
    no_enc = 0
    plaint_mac = data_desc([],[],[],0)
    if i_sec_proc_state == "INT_MOVE":
        enc_data_list.append(i_proc_data)
        no_enc = 1
        if i_int_done :
            enc_data_list.append(i_mac_clac_data)
    elif i_sec_proc_state == "INT2ENC":
        enc_data_list.append(i_proc_data)
        if i_int_done and i_mac_append: # as
            enc_data_list.append(i_mac_clac_data)
    elif i_sec_proc_state == "ENC2INT":
        # TODO 注意 此时的mac 也需要放到 outfifo中
        int_data_list.append(i_pre_aad_data)
        if i_mac_append: # as
            # 拆开mac和polayload
            plaint_mac = pop_word_from_data_desc(i_cipher_data)
            int_data_list.append(i_cipher_data)
        else:
            int_data_list.append(i_cipher_data)

    int_seg_num = len(int_data_list)
    int_total_seg_bytes = []
    for i in range(int_seg_num):
        seg_bytes += int_data_list[i].data_len
    int_total_seg_bytes.append(seg_bytes)
    int_data = int_sec_fifo.run(int_data_list,int_seg_num,0.02,int_total_seg_bytes,1,False,0.05)

    enc_seg_num = len(enc_data_list)
    enc_total_seg_bytes = []
    for i in range(enc_seg_num):
        seg_bytes += enc_data_list[i].data_len
    enc_total_seg_bytes.append(seg_bytes)
    enc_data = enc_sec_fifo.run(enc_data_list,enc_seg_num,0.02,enc_total_seg_bytes,1,False,0.05)

    return int_data,enc_data,plaint_mac

    # start sec-core


        
    
if __name__ == "__main__":
    #input
    #state
    # 1. 
    i_sec_proc_state = "IDLE"
    i_hdr_en = 0

    # 原始输入
    i_pre_aad_data = data_desc()
    i_proc_data = data_desc()
    i_mac_load_data = data_desc()
    i_head_data = data_desc()

    # 输出
    o_enc_data = 0
    o_int_data = 0

    # 中间输入
    i_cipher_data = 0
    i_mac_clac_data = 0
    i_int_done = 0