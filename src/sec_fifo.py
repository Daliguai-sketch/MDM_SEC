from src.sec_class_define import data_desc
from typing import List,Optional
from collections import deque
import queue
import math
import copy
import time
import threading

# 先后顺序由List决定
# 输入列表， 串行到达， List[data0,data1,data2...]
# FIFO
# 输出列表： 根据配置重新打包成N路输出，每路有固定字节数。串行输出
class sec_fifo:
    def __init__(self,fifo_depth:int=64):
        self.max_bytes = fifo_depth
        self.fifo = queue.Queue(maxsize=self.max_bytes)

        # in/output List
        self.o_data = [] # 元素是 data_desc,根据[len1,len2,len3...]给出
        #self.i_data = [] # 元素是 data_desc, 
        self.out_lock = threading.Lock()

        # 控制
        self.running = True
        self.write_done = False
        self.read_done = False

        # 统计
        self.written_bytes = 0
        self.read_bytes = 0

    def write_word(self,data:int,valid_bytes:int) -> bool:
        if (self.fifo.qsize() + valid_bytes > self.max_bytes):
            return False
        try:
            for i in range(valid_bytes):
                byte = (data >> (8*(4-i-1))) & 0xFF
                self.fifo.put(byte,timeout=0.1)
        except queue.Full:
            raise
        self.written_bytes += valid_bytes
        return True
    
    def read_word(self,valid_bytes:int):
        if self.fifo.qsize() < valid_bytes:
            raise queue.Empty
        word = 0
        for i in range(valid_bytes):
            try:
                byte = self.fifo.get_nowait()
                word |= (byte << (8*(4-i-1)))
                self.read_bytes += 1
            except queue.Empty:
                raise
        #if valid_bytes != 4:
        #    word = word << (4-valid_bytes)
        return word

    def stop(self,read_byte_len):
        if self.write_done and self.written_bytes != read_byte_len:
            print("Input: "+str(self.written_bytes) + " and Output: " + str(self.read_bytes) + ", 请检查程序")
            self.running = False

    def finish(self):
        self.running = False

    def _add_out(self,channel_idx:int,word,last:int):
        #if word is None:
        #    return
        a = 0
        with self.out_lock:
            hex_str = f"0x{word:08X}"
            self.o_data[channel_idx].data.append(hex_str)
            self.o_data[channel_idx].data_vld.append(1)
            self.o_data[channel_idx].last.append(last)

    # 写线程
    def write_thread(self,i_data:List[data_desc] = None,i_data_channel_num:int=1,delay:float = 0.05):
        print("写线程启动")
        for i in range(i_data_channel_num):
            if not self.running:
                break
            data_seg = copy.deepcopy(i_data[i])
            # 允许输入字段为0，
            if data_seg.data_len == 0:
                continue
            data_idx = 0
            while(True):
                valid_bytes = 4
                if data_seg.last[data_idx] :
                    # the last
                    valid_bytes = (data_seg.data_len - 1) % 4 + 1
                # FIFO 满时等待
                wait_count = 0
                while self.fifo.qsize() + valid_bytes > self.max_bytes:
                    if not self.running:
                        break
                    wait_count += 1
                    if wait_count % 10 == 0:
                        print(f"FIFO满,等待......({self.fifo.qsize()}/{self.max_bytes})")
                    time.sleep(0.02)
                self.write_word(data_seg.data[data_idx],valid_bytes)
                time.sleep(delay)
                if data_seg.last[data_idx] :
                    break
                data_idx += 1               
        self.write_done = True
        print("写线程结束，共写入" + str(self.written_bytes) + "个字节")

    # 读线程
    def read_thread(self,bytes_out_data_list:List,out_data_channel_num: int = 1, drop_1st:bool = False, delay:float = 0.02):
        '''
        读线程:持续读取并拼接
        bytes_out_data_list: [len1,len2,len3.....], 输出拆分标志
        out_data_channel_num: list长度
        '''
        print("读线程启动")

        seg_idx = 0
        word_idx = 0
        data_buf = data_desc([],[],[],0)
        out_byte_len = 0
        for i in range(out_data_channel_num):
            out_byte_len += bytes_out_data_list[i]
        while self.running:
            if self.write_done:
                debug = 0
            a = 0 
            try:
                while (seg_idx < out_data_channel_num):
                    seg_byte_len = bytes_out_data_list[seg_idx]
                    # 允许输出字段为0， 保留位置
                    if seg_byte_len == 0:
                        if not (seg_idx == 0 and drop_1st):
                            self.o_data.append(copy.deepcopy(data_buf))
                        seg_idx += 1
                        if seg_idx == out_data_channel_num:
                            self.read_done = True
                            self.finish()
                            break
                        continue
                    seg_word_len = math.ceil(seg_byte_len / 4)
                    last_word_byte_len = (seg_byte_len - 1) % 4 + 1
                    last_word_idx = seg_word_len - 1

                    #print("#####")
                    print("read_channel_idx: " + str(seg_idx))
                    if drop_1st:
                        o_idx = seg_idx-1
                    else:
                        o_idx = seg_idx
                    
                    # 检查是否丢弃第一个字段
                    if seg_idx == 0 and drop_1st:  
                        while(word_idx <= last_word_idx):
                            if word_idx == last_word_idx:
                                word = self.read_word(last_word_byte_len)
                                word_idx = 0
                                seg_idx += 1
                                break
                            word = self.read_word(4)
                            word_idx += 1
                        continue
                    # 其他字段
                    while(word_idx <= last_word_idx):
                        # last_word
                        if word_idx == last_word_idx:
                            word = self.read_word(last_word_byte_len)
                            data_buf.add_element(word,1,last_flag=1)
                            word_idx = 0
                            data_buf.update_data_len(seg_byte_len)
                            self.o_data.append(copy.deepcopy(data_buf))
                            data_buf.clear()
                            if seg_idx == out_data_channel_num - 1:
                                self.read_done = True
                                self.finish()

                            seg_idx += 1
                            break
                        # other word                    
                        word = self.read_word(4)
                        data_buf.add_element(word,1,last_flag=0)
                        word_idx += 1
                    
            except queue.Empty:
                print("读为空")
                if self.write_done and self.fifo.qsize() == 0:
                    if self.write_done:
                        self.stop(self.read_bytes)
                    # 检查数据个数
                    elif self.written_bytes == self.read_bytes:
                        print("输入输出数据个数相同")
                    else:
                        print("Input: "+str(self.written_bytes) + " and Output: " + str(self.read_bytes) + ", 请检查程序")
                    break
                time.sleep(0.05)
                continue
            time.sleep(delay)
        self.read_done = True
        print("读线程结束，共读出" + str(self.read_bytes) + "个字节")

                
    def run(self,i_data:List[data_desc] = None,i_data_channel_num:int=1,write_delay:float=0.05,bytes_out_data_list:List[int] = 0,out_data_channel_num: int = 1, drop_1st:bool = False, read_delay:float = 0.02):
        """
        并行处理
        Args:
            i_data:[data_desc1,data_desc2,....]
            i_data_channel_num:  输入几路数据
            write_delay: 写数据延迟
            bytes_out_data_list: [len1,len2,len3.....], 定义输出数据每段长度
            out_data_channel_num: 输出数据路数
            drop_1st: 数据数据中第一路数据是否保留，默认保留， 1:丢弃,0:保留
            read_delay: 读数据延迟
        Return:
            输出数据列表
        """
        # 创建线程
        writer = threading.Thread(target=self.write_thread,args=(i_data,i_data_channel_num,write_delay))
        reader = threading.Thread(target=self.read_thread,args=(bytes_out_data_list,out_data_channel_num,drop_1st,read_delay))

        print("启动并行")
        writer.start()
        reader.start()

        # 等待
        writer.join()
        reader.join()
        #print(f"共输出{self.read_bytes}个字节")
        return self.o_data


if __name__ == "__main__":
    #input
    i_fifo_depth = 64 # 64/4=16 words
    i_data = List(data_desc())
    o_data = data_desc()
    i_data_channel_num = 1