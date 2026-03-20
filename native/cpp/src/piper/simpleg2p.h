// Piper TTS - Simple Grapheme-to-Phoneme
// Based on nihui/ncnn-android-piper (BSD 3-Clause)
// Adapted for EdgeMind: removed AAssetManager, file-path only

#ifndef SIMPLEG2P_H
#define SIMPLEG2P_H

#include <map>
#include <vector>
#include <string>

class SimpleG2P
{
public:
    void load(const char* lang);
    void clear();

    void find(const char* word, const unsigned char*& ids) const;
    void phonemize(const char* text, std::vector<int>& sequence_ids) const;

protected:
    int get_char_width(const char* pchar) const;
    unsigned int get_first_char(const char* word) const;

protected:
    std::vector<unsigned char> en_dictbinbuf;
    std::map<unsigned int, std::vector<const char*> > en_dict;

    std::vector<unsigned char> dictbinbuf;
    std::map<unsigned int, std::vector<const char*> > dict;
};

#endif // SIMPLEG2P_H
