-- 1. TABEL WALLETS
CREATE TABLE wallets (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  balance NUMERIC DEFAULT 0,
  type TEXT CHECK (type IN ('cash', 'cashless')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. TABEL TRANSACTIONS
CREATE TABLE transactions (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  wallet_id UUID REFERENCES wallets(id) ON DELETE CASCADE,
  amount NUMERIC NOT NULL,
  description TEXT,
  category TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. TABEL DEBTS
CREATE TABLE debts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  person_name TEXT NOT NULL,
  amount NUMERIC NOT NULL,
  remaining_amount NUMERIC NOT NULL,
  is_debt BOOLEAN DEFAULT true,
  is_settled BOOLEAN DEFAULT false,
  wallet_id UUID REFERENCES wallets(id) ON DELETE SET NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 4. FUNCTION UPDATE SALDO
CREATE OR REPLACE FUNCTION update_wallet_balance(w_id UUID, amount_change NUMERIC)
RETURNS VOID AS $$
BEGIN
  UPDATE wallets
  SET balance = balance + amount_change
  WHERE id = w_id;
END;
$$ LANGUAGE plpgsql;

-- 5. SETUP STORAGE AVATARS
-- Jalankan ini untuk mengizinkan akses ke folder avatars
INSERT INTO storage.buckets (id, name, public) VALUES ('avatars', 'avatars', true);

-- Policy agar user hanya bisa upload avatar mereka sendiri
CREATE POLICY "Avatar upload by owner" ON storage.objects
FOR INSERT WITH CHECK (bucket_id = 'avatars' AND auth.uid() = owner);

CREATE POLICY "Avatar update by owner" ON storage.objects
FOR UPDATE WITH CHECK (bucket_id = 'avatars' AND auth.uid() = owner);

CREATE POLICY "Public Access to Avatars" ON storage.objects
FOR SELECT USING (bucket_id = 'avatars');