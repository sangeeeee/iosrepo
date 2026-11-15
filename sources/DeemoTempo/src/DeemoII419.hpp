#pragma once
#include <cstdint>
namespace deemo2 {
struct Entry { uint32_t offset,word; };
constexpr Entry frame{0x43da804,0x6dba23e9};
constexpr Entry songTime{0x43c73ac,0xa9be4ff4};
constexpr Entry setTime{0x43cb8f8,0x6dbd23e9};
constexpr Entry normalSong{0x43db398,0xa9be4ff4};
constexpr Entry getSong{0x43d3b80,0xa9be4ff4};
constexpr Entry volume{0x43d4194,0xa9be4ff4};
constexpr Entry syncAudio{0x43cba50,0xd100c3ff};
constexpr Entry syncChart{0x43d8c18,0x6dbc23e9};
constexpr Entry calibratedMS{0x43cb03c,0x6dbd23e9};
constexpr Entry jump{0x43d905c,0xd10143ff};
constexpr Entry disableNotes{0x43c1378,0xa9bc5ff8};
constexpr Entry updatePlane{0x43c16f0,0xa9bd57f6};
constexpr Entry spawn{0x43c1ba4,0xa9bd57f6};
constexpr Entry sound{0x43c2010,0x6dbc23e9};
constexpr Entry resetKey{0x43c6064,0xa9be4ff4};
constexpr Entry cancelKey{0x43c600c,0xa9be4ff4};
constexpr Entry stopID{0x43f7a3c,0xa9bd57f6};
constexpr Entry cancelCallback{0x43f7b3c,0xa9bd57f6};
constexpr Entry resultInit{0x43e2b94,0xa9bd57f6};
constexpr Entry resetResult{0x43e2c14,0x6dbb23e9};
constexpr Entry addJudge{0x43e33f4,0x6db82beb};
constexpr Entry judge{0x43bec20,0xd10283ff};
constexpr Entry settle{0x43e4274,0xa9bd57f6};
constexpr Entry showResultAnimation{0x43d0fc8,0xa9be4ff4};
constexpr Entry resultDone{0x43d6d0c,0x52800028};
constexpr Entry loadPlane{0x43d2c20,0xa9bb67fa};
constexpr Entry release{0x43d7bcc,0xf9401c00};
constexpr Entry isPaused{0x43d8af8,0x39426000};
constexpr Entry hasBank{0x43f56f8,0xd10103ff};
constexpr Entry tryBank{0x3c47bac,0xa9bd57f6};
constexpr Entry decode{0x16d5dac,0xd10343ff};
constexpr Entry action{0x15f1514,0xa9be4ff4};
constexpr Entry pauseMusic{0x43d3c84,0xa9bd57f6};
constexpr Entry resumeMusic{0x43d3e10,0x6dbc23e9};
constexpr Entry activeSound{0x43c1f04,0xa9bd57f6},retry{0x43d5210,0x6db923e9};
constexpr Entry entries[]={frame,songTime,setTime,normalSong,getSong,volume,syncAudio,syncChart,calibratedMS,jump,disableNotes,updatePlane,spawn,sound,resetKey,cancelKey,stopID,cancelCallback,resultInit,resetResult,addJudge,judge,settle,showResultAnimation,resultDone,loadPlane,release,isPaused,hasBank,tryBank,decode,action,pauseMusic,resumeMusic,activeSound,retry};
constexpr uint8_t uuid[]={0xc5,0xc5,0x7a,0x16,0x43,0xe8,0x3d,0xf4,0xa1,0xb2,0xd8,0x8e,0x89,0x44,0x9b,0x21};
}
