import brotli
import sys
import os

if len(sys.argv) != 3:
    print("Usage: python decompress_br.py <input.br> <output.dat>")
    sys.exit(1)

input_file = sys.argv[1]
output_file = sys.argv[2]

if not os.path.exists(input_file):
    print(f"Error: {input_file} not found.")
    sys.exit(1)

print(f"Decompressing {input_file} to {output_file}...")

try:
    with open(input_file, 'rb') as f_in, open(output_file, 'wb') as f_out:
        d = brotli.Decompressor()
        while True:
            chunk = f_in.read(1024 * 1024 * 8) # 8 MB chunks
            if not chunk:
                break
            f_out.write(d.process(chunk))
        pass  # All data flushed during process()
    print("Decompression complete!")
except Exception as e:
    print(f"Error during decompression: {e}")
