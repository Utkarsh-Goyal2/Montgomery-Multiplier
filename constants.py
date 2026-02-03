def mod_inv(a, m):
    """Compute the modular inverse of a under modulo m using Extended Euclidean Algorithm."""
    m0, x0, x1 = m, 0, 1
    if m == 1:
        return 0
    while a > 1:
        q = a // m
        m, a = a % m, m
        x0, x1 = x1 - q * x0, x0
    if x1 < 0:
        x1 += m0
    return x1

def find_R(m):
    """Find R such that R > m and gcd(R, m) = 1, where R is a power of 2."""
    R = 1
    while R <= m:
        R <<= 1
    return R

def find_constants(m):
    R = find_R(m)
    R2 = (R * R) % m
    m_inv = (-mod_inv(m, R)) % R
    return R, R2, m_inv

if __name__ == "__main__":
    s = input("Enter modulus m (decimal, binary like 0b1010 or plain 1010, or hex like 0x1A): ").strip()
    if s.lower().startswith('0b'):
        mm = int(s, 2)
    elif s.lower().startswith('0x'):
        mm = int(s, 16)
    elif all(ch in '01_' for ch in s) and any(ch in '01' for ch in s):
        # plain sequence of 0/1 (underscores allowed) -> treat as binary
        mm = int(s.replace('_', ''), 2)
    else:
        # fallback: decimal or other Python numeric literal
        mm = int(s, 0)
    R, R2, m_inv = find_constants(mm)
    print(f"R: {hex(R)}, R2: {hex(R2)}, m_inv: {hex(m_inv)}")