a = int(input("Enter a (hex): "), 16)
b = int(input("Enter b (hex): "), 16)
m = 0xFFFFFFFFFFFFFFF1
print(f"a * b mod m = {hex((a * b) % m)}")