import sys

path = "/scratch/mjk76/ea442/promptstudy/libgdx-s5.dtrace"
max_len = 0
max_line_no = 0
cur_len = 0
line_no = 1

with open(path, "rb") as f:
    while True:
        chunk = f.read(1 << 20)
        if not chunk:
            break
        for b in chunk:
            if b == 0x0A:  # newline
                if cur_len > max_len:
                    max_len = cur_len
                    max_line_no = line_no
                cur_len = 0
                line_no += 1
            else:
                cur_len += 1

print(f"max line length: {max_len} bytes, at line {max_line_no}")
