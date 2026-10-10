from src.sec_class_define import data_desc
from sec_top.sec_process.sec_recomb_packet_data import pop_word_from_data_desc
from sec_core.sec_core_ctrl import run_sec_core
from src.sec_fifo import sec_fifo

class sec_proc_fsm():
    def __init__(self,i_hdr_en,i_move_en,i_int_en,i_enc_en,i_sec_mode,i_error):
        self.state = "IDLE"
        self.hdr_en = i_hdr_en
        self.move_en = i_move_en
        self.int_en = i_int_en
        self.enc_en = i_enc_en
        self.sec_mode = i_sec_mode
        self.error = i_error
        self.int_data_list = []
        self.enc_data_list = []
        self.out_fifo_list = []

        self.int_done = 0
        self.enc_done = 0
        if self.hdr_en :
            self.hdr_done = 1
        else:
            self.hdr_done = 0

        self.int_data = data_desc([],[],[],0)
        self.enc_data = data_desc([],[],[],0)
        self.mac_calc_data = data_desc([],[],[],0)
        self.plaint_mac = data_desc([],[],[],0)
        self.cipher_data = data_desc([],[],[],0)

    def get_data_seg_seg_and_bytes(self,data_list):
        seg_num = len(data_list)
        bytes_num = []
        bytes = 0
        for i in range(seg_num):
            bytes += data_list[i].data_len
        bytes_num.append(bytes)

        return seg_num,bytes_num

    def sec_proc_ctrl_state(self,i_head_data,i_proc_data,i_pre_aad_data,i_mac_append,i_int_alg_id,i_enc_alg_id,i_count,i_bearer,i_direction,i_int_key,i_enc_key):
        tmp_sec_fifo = sec_fifo(64)
        write_delay = 0.05
        read_delay = 0.02
        drop_first = False                                        
        if self.state == "IDLE":
            if self.hdr_en: 
                self.state = "HEAD"
            elif self.int_en and (self.sec_mode == 1 or self.sec_mode == 2):
                self.state = "INT"
            elif self.move_en:
                self.state = "MOVE"
            elif self.enc_en and (self.sec_mode == 0 or self.sec_mode == 3):
                self.state = "ENC"
        elif self.state == "MOVE":
            # to out
            self.out_fifo_list.append(i_proc_data)
            if self.int_en and self.int_done:
                self.out_fifo_list.append(self.mac_calc_data)
            self.state = "DONE"
        elif self.state == "HEAD":
            if self.hdr_done :
                self.out_fifo_list.append(i_head_data)
                if self.int_en:
                    self.int_data_list.append(i_head_data)                                     
                    self.state = "INT"
                elif self.enc_en :
                    self.state = "ENC"
                elif self.move_en:
                    self.state = "MOVE"
                else:
                    self.state = "DONE" 
        elif self.state == "INT":
            self.int_data_list.append(i_pre_aad_data)
            if self.sec_mode == 3 and self.enc_done:
                self.int_data_list.append(self.cipher_data)
            else:
                self.int_data_list.append(i_proc_data)
            # run
            seg_num,total_bytes = self.get_data_seg_seg_and_bytes(self.int_data_list)
            out_data_channel_num = 1
            tmp_data_list = tmp_sec_fifo.run(self.int_data_list,seg_num,write_delay,total_bytes,out_data_channel_num,drop_first,read_delay)
            self.int_data = tmp_data_list.pop()
            run_sec_core(1,1,i_int_alg_id,i_enc_alg_id,i_count,i_bearer,i_direction,i_int_key,i_enc_key,self.enc_data,self.int_data,self.cipher_data,self.mac_calc_data)
            self.int_done = 1

            if self.int_done :
                if self.move_en:
                    self.state = "MOVE"
                elif self.sec_mode == 2:
                    self.state = "ENC"
                else:
                    self.state = "DONE" 
        elif self.state == "ENC":
            self.enc_data_list.append(i_proc_data)
            if self.sec_mode == 2 and i_mac_append and self.int_done:
                self.enc_data_list.append(self.mac_calc_data)
            # run
            seg_num,total_bytes = self.get_data_seg_seg_and_bytes(self.enc_data_list)
            out_data_channel_num = 1
            tmp_data_list = tmp_sec_fifo.run(self.enc_data_list,seg_num,write_delay,total_bytes,out_data_channel_num,drop_first,read_delay)
            self.enc_data = tmp_data_list.pop()
            run_sec_core(0,1,i_int_alg_id,i_enc_alg_id,i_count,i_bearer,i_direction,i_int_key,i_enc_key,self.enc_data,self.int_data,self.cipher_data,self.mac_calc_data)
            self.enc_done = 1
            self.out_fifo_list.append(self.cipher_data)

            if self.enc_done:
                if self.sec_mode == 3 and i_mac_append:
                    self.plaint_mac = pop_word_from_data_desc(self.cipher_data)
                    self.state = "INT"
                if self.sec_mode == 3:
                    self.state = "INT"
                else:
                    self.state = "DONE"
        elif self.error:
            self.state = "DONE"

        return self.state,self.plaint_mac,self.out_fifo_list

    def run_sec_proc(self,i_head_data,i_proc_data,i_pre_aad_data,i_mac_append,i_int_alg_id,i_enc_alg_id,i_count,i_bearer,i_direction,i_int_key,i_enc_key):

        cur_state = "IDLE"
        while(True):
            nxt_state,plaint_mac,out_fifo_list = self.sec_proc_ctrl_state(i_head_data,i_proc_data,i_pre_aad_data,i_mac_append,i_int_alg_id,i_enc_alg_id,i_count,i_bearer,i_direction,i_int_key,i_enc_key)
            print(nxt_state)
            if cur_state == "INT":
                print("###############CALC_MAC##############")
                print(hex(self.mac_calc_data.data[0]))
                #if plaint_mac.data:
                #    print("###############LOAD_MAC_PLAINT##############")
                #    print(hex(self.mac_calc_data.data[0]))
            elif nxt_state == "DONE":
                # out_fifo
                out_sec_fifo = sec_fifo(64)
                write_delay = 0.05
                read_delay = 0.02
                drop_first = False
                out_total_bytes = []
                out_total_bytes.append(0)
                for i in range(len(out_fifo_list)):
                    out_total_bytes[0] += out_fifo_list[i].data_len
                tmp_output_data = out_sec_fifo.run(out_fifo_list,len(out_fifo_list),write_delay,out_total_bytes,1,drop_first,read_delay)
                print("###############OUTPUT_FIFO##############")
                output_data = tmp_output_data[0]
                for i in range(len(output_data.data)):
                    print(f"0x{output_data.data[i]:08x}")
                break
            cur_state = nxt_state
        return output_data,self.mac_calc_data

if __name__ == "__main__":
    #ctrl
    i_hdr_en = 0
    i_move_en = 0
    i_int_en = 0
    i_enc_en = 0
    i_sec_mode = 0
    i_move_done = 0

    #data load_packet
    i_pre_aad_data = data_desc()
    i_proc_data = data_desc()
    i_mac_data = data_desc()
    i_hdr_data = data_desc()
