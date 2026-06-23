//+------------------------------------------------------------------+
//|                                              ScalpingStrategy.mq5|
//|                                  Copyright 2026, AI Trading Corp|
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, AI Trading Corp"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "EA Scalping berdasarkan Strategi Kemenangan 90%"

// Menggunakan library bawaan MT5 untuk eksekusi trade
#include <Trade\Trade.mqh>
CTrade trade;

//--- Input Parameters (Dapat diubah di menu setting EA)
input group "=== Parameter Transaksi ==="
input double   InpLotSize        = 0.1;       // Ukuran Lot (Dapat Diubah)
input double   InpTakeProfitPct  = 2.0;       // Take Profit (%)
input double   InpStopLossPct    = 1.0;       // Stop Loss (%)
input ulong    InpMagicNumber    = 909090;    // Magic Number EA

input group "=== Parameter Indikator ==="
input int      InpEMA_Cepat      = 9;         // Periode EMA Cepat
input int      InpEMA_Lambat     = 21;        // Periode EMA Lambat
input int      InpRSI_Period     = 14;        // Periode RSI
input int      InpMACD_Fast      = 12;        // MACD Fast EMA
input int      InpMACD_Slow      = 26;        // MACD Slow EMA
input int      InpMACD_Signal    = 9;         // MACD Signal Period

//--- Global Handles Indikator
int emaCepatHandle;
int emaLambatHandle;
int rsiHandle;
int macdHandle;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Set ID unik untuk transaksi dari EA ini
   trade.SetExpertMagicNumber(InpMagicNumber);
   
   // Inisialisasi Indikator ke dalam memory MetaTrader 5
   emaCepatHandle  = iMA(_Symbol, _Period, InpEMA_Cepat, 0, MODE_EMA, PRICE_CLOSE);
   emaLambatHandle = iMA(_Symbol, _Period, InpEMA_Lambat, 0, MODE_EMA, PRICE_CLOSE);
   rsiHandle       = iRSI(_Symbol, _Period, InpRSI_Period, PRICE_CLOSE);
   macdHandle      = iMACD(_Symbol, _Period, InpMACD_Fast, InpMACD_Slow, InpMACD_Signal, PRICE_CLOSE);
   
   // Validasi jika indikator gagal dimuat
   if(emaCepatHandle == INVALID_HANDLE || emaLambatHandle == INVALID_HANDLE || 
      rsiHandle == INVALID_HANDLE || macdHandle == INVALID_HANDLE)
   {
      Print("Gagal menginisialisasi indikator.");
      return(INIT_FAILED);
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Menghapus handle untuk menghemat ram pc/vps
   IndicatorRelease(emaCepatHandle);
   IndicatorRelease(emaLambatHandle);
   IndicatorRelease(rsiHandle);
   IndicatorRelease(macdHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Sistem mendeteksi berdasarkan Candle Baru yang sudah close (menghindari false signal)
   static datetime lastBarTime;
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime == lastBarTime) return;
   
   // Array penampung nilai indikator
   double emaCepat[], emaLambat[], rsi[];
   double macdMain[], macdSignal[];
   
   // Copy data candle dan indikator sebelumnya (Indeks 0 = candle t-1 yang baru saja Close)
   MqlRates rates[];
   if(CopyRates(_Symbol, _Period, 1, 2, rates) < 2) return;
   if(CopyBuffer(emaCepatHandle, 0, 1, 2, emaCepat) < 2) return;
   if(CopyBuffer(emaLambatHandle, 0, 1, 2, emaLambat) < 2) return;
   if(CopyBuffer(rsiHandle, 0, 1, 2, rsi) < 2) return;
   if(CopyBuffer(macdHandle, 0, 1, 2, macdMain) < 2) return;
   if(CopyBuffer(macdHandle, 1, 1, 2, macdSignal) < 2) return;
   
   // Mengurutkan array agar data terbaru berada di indeks [0]
   ArraySetAsSeries(emaCepat, true);
   ArraySetAsSeries(emaLambat, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(macdMain, true);
   ArraySetAsSeries(macdSignal, true);
   ArraySetAsSeries(rates, true);
   
   double priceClose = rates[0].close;
   
   // Menghitung jumlah posisi aktif yang dibuka oleh EA ini
   int totalPositions = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
      {
         totalPositions++;
      }
   }
   
   // Eksekusi jika tidak ada posisi yang sedang berjalan (Manajemen Risiko)
   if(totalPositions == 0)
   {
      // -------------------------------------------------------------
      // 1. SETUP BELI (BUY)
      // -------------------------------------------------------------
      bool emaCrossUp  = (emaCepat[0] > emaLambat[0]) && (emaCepat[1] <= emaLambat[1]); // EMA 9 Menyilang ke atas EMA 21
      bool rsiBuyCond  = (rsi[0] > 50.0);                                              // RSI(14) > 50
      bool macdBuyCond = (macdMain[0] > macdSignal[0]);                                // Garis MACD di atas Sinyal
      
      if(emaCrossUp && rsiBuyCond && macdBuyCond)
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         
         // Kalkulasi Persentase TP 2% & SL 1% dari harga close candle konfirmasi
         double slDistance = priceClose * (InpStopLossPct / 100.0);
         double tpDistance = priceClose * (InpTakeProfitPct / 100.0);
         
         double slPrice = NormalizeDouble(ask - slDistance, _Digits);
         double tpPrice = NormalizeDouble(ask + tpDistance, _Digits);
         
         if(trade.Buy(InpLotSize, _Symbol, ask, slPrice, tpPrice, "Scalping 90% BUY"))
         {
            lastBarTime = currentBarTime;
            return;
         }
      }
      
      // -------------------------------------------------------------
      // 2. SETUP JUAL (SELL)
      // -------------------------------------------------------------
      bool emaCrossDown = (emaCepat[0] < emaLambat[0]) && (emaCepat[1] >= emaLambat[1]); // EMA 9 Menyilang ke bawah EMA 21
      bool rsiSellCond  = (rsi[0] < 50.0);                                              // RSI(14) < 50
      bool macdSellCond = (macdMain[0] < macdSignal[0]);                                // Garis MACD di bawah Sinyal
      
      if(emaCrossDown && rsiSellCond && macdSellCond)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         
         // Kalkulasi Persentase TP 2% & SL 1% dari harga close candle konfirmasi
         double slDistance = priceClose * (InpStopLossPct / 100.0);
         double tpDistance = priceClose * (InpTakeProfitPct / 100.0);
         
         double slPrice = NormalizeDouble(bid + slDistance, _Digits);
         double tpPrice = NormalizeDouble(bid - tpDistance, _Digits);
         
         if(trade.Sell(InpLotSize, _Symbol, bid, slPrice, tpPrice, "Scalping 90% SELL"))
         {
            lastBarTime = currentBarTime;
            return;
         }
      }
   }
}
//+------------------------------------------------------------------+