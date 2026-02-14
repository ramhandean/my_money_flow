# MyMoneyFlow 💸

Aplikasi pengelola keuangan pribadi (Personal Finance Management) yang dibangun dengan **Flutter** dan **Supabase**. Didesain khusus untuk user dengan mobilitas tinggi, aplikasi ini memiliki sistem **Offline-First** yang tangguh untuk mencatat transaksi kapan saja, bahkan saat sinyal hilang di perjalanan.

## ✨ Fitur Unggulan

* **Offline-First & Auto-Sync**: Catat transaksi saat offline, dan aplikasi akan mensinkronisasinya secara otomatis saat kembali online.
* **Race Condition Protection**: Sistem penguncian (**Atomic Lock**) untuk mencegah duplikasi data transaksi dan pemotongan saldo ganda pada koneksi tidak stabil.
* **Instant Dashboard**: Saldo dashboard langsung berubah seketika (Optimistic UI) tanpa menunggu respon server.
* **Multi-Wallet Management**: Kelola banyak dompet sekaligus (Tunai, Bank, E-Wallet).
* **Hutang & Piutang**: Pantau pinjaman dan hutang dengan status pelunasan yang terintegrasi ke saldo utama.
* **Smart Insight**: Peringatan otomatis jika pengeluaran bulanan sudah mendekati batas budget (Rp3.000.000).
* **Dark & Light Mode**: Tampilan elegan yang menyesuaikan dengan tema sistem perangkat.

## 🚀 Tech Stack

* **Frontend**: [Flutter](https://flutter.dev) (Dart)
* **Backend**: [Supabase](https://supabase.com) (Auth, Database, Storage, RPC Functions)
* **Local Storage**: `shared_preferences` untuk caching dan queueing.
* **State Management**: `StatefulWidget` dengan variabel `Future` yang dioptimasi untuk mencegah rebuild berlebih.

## 🛠️ Persiapan & Instalasi

1.  **Clone Repository**
    ```bash
    git clone [https://github.com/username/my_money_flow.git](https://github.com/username/my_money_flow.git)
    cd my_money_flow
    ```

2.  **Setup Environment**
    Salin file `.env.sample` menjadi `.env` dan isi dengan kredensial Supabase lu:
    ```bash
    cp .env.sample .env
    ```

3.  **Database & Storage Setup**
    - Buka **SQL Editor** di Dashboard Supabase.
    - Copy dan jalankan isi dari file `database.sql` yang ada di root project untuk membuat tabel, fungsi RPC, dan setup Storage.
    - Pastikan bucket `avatars` sudah dibuat di menu **Storage** dengan akses public.

4.  **Install Dependencies & Run**
    ```bash
    flutter pub get
    flutter run
    ```

## 🏗️ Alur Sinkronisasi Data (Bulletproof Sync)

Aplikasi menggunakan sistem antrean sinkron (Synchronized Queue) untuk menjaga integritas data:
1.  **Optimistic UI**: Transaksi disimpan ke list lokal & saldo di cache HP langsung dipotong agar user melihat perubahan instan.
2.  **Background Processing**: Aplikasi mencoba menjalankan antrean secara berurutan (FIFO).
3.  **Atomic Lock**: Menggunakan `Future` locking untuk mencegah dua proses sync berjalan bersamaan.
4.  **Verification**: Antrean hanya dihapus dari storage HP jika Supabase mengembalikan respon sukses. Jika terjadi kegagalan koneksi, antrean tetap tersimpan untuk dicoba kembali nanti.

---
Dibuat dengan ❤️ oleh **Dean Ramhan** untuk menemani perjalanan mudik ke Sukabumi! 🚗💨