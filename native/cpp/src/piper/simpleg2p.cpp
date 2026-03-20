// Piper TTS - Simple Grapheme-to-Phoneme
// Based on nihui/ncnn-android-piper (BSD 3-Clause)
// Adapted for EdgeMind: removed AAssetManager, file-path only

#include "simpleg2p.h"

#include <stdio.h>
#include <string.h>
#include <ctype.h>

void SimpleG2P::load(const char* lang)
{
    // lang may be an absolute path like "/data/.../piper_tts/en"
    // Extract directory to construct sibling file paths
    std::string lang_str(lang);
    std::string dir;
    size_t slash = lang_str.rfind('/');
    if (slash != std::string::npos)
        dir = lang_str.substr(0, slash + 1);

    std::string en_bin_path = dir + "en-word_id.bin";
    std::string lang_bin_path = lang_str + "-word_id.bin";

    // load en dict buffer
    {
        FILE* fp = fopen(en_bin_path.c_str(), "rb");
        if (!fp) {
            fprintf(stderr, "SimpleG2P: failed to open %s\n", en_bin_path.c_str());
            return;
        }

        fseek(fp, 0, SEEK_END);
        size_t len = ftell(fp);
        rewind(fp);

        en_dictbinbuf.resize(len);
        fread(en_dictbinbuf.data(), 1, len, fp);
        fclose(fp);
    }

    // build en dict
    {
        const unsigned char* p = en_dictbinbuf.data();
        const char* word = (const char*)p;

        for (size_t i = 0; i < en_dictbinbuf.size(); i++)
        {
            if (en_dictbinbuf[i] == 0xff)
            {
                unsigned int first_char = get_first_char(word);
                en_dict[first_char].push_back(word);
                word = (const char*)(p + i + 1);
            }
        }
    }

    // For English-only, skip lang dict
    const char* base = strrchr(lang, '/');
    std::string langCode = base ? std::string(base + 1) : std::string(lang);
    if (langCode == "en" || langCode.empty())
        return;

    // load lang dict buffer
    {
        FILE* fp = fopen(lang_bin_path.c_str(), "rb");
        if (!fp) return;

        fseek(fp, 0, SEEK_END);
        size_t len = ftell(fp);
        rewind(fp);

        dictbinbuf.resize(len);
        fread(dictbinbuf.data(), 1, len, fp);
        fclose(fp);
    }

    // build lang dict
    {
        const unsigned char* p = dictbinbuf.data();
        const char* word = (const char*)p;

        for (size_t i = 0; i < dictbinbuf.size(); i++)
        {
            if (dictbinbuf[i] == 0xff)
            {
                unsigned int first_char = get_first_char(word);
                dict[first_char].push_back(word);
                word = (const char*)(p + i + 1);
            }
        }
    }
}

void SimpleG2P::clear()
{
    en_dictbinbuf.clear();
    en_dict.clear();
    dictbinbuf.clear();
    dict.clear();
}

void SimpleG2P::find(const char* word, const unsigned char*& ids) const
{
    ids = 0;

    unsigned int first_char = get_first_char(word);

    if (isdigit(word[0]))
    {
        if (dict.find(first_char) != dict.end())
        {
            const std::vector<const char*>& wordlist = dict.at(first_char);
            for (size_t i = 0; i < wordlist.size(); i++)
            {
                if (strcasecmp(wordlist[i], word) == 0)
                {
                    ids = (const unsigned char*)(wordlist[i] + strlen(wordlist[i]) + 1);
                    return;
                }
            }
        }

        // fallback to en
        if (en_dict.find(first_char) == en_dict.end())
            return;

        const std::vector<const char*>& wordlist = en_dict.at(first_char);
        for (size_t i = 0; i < wordlist.size(); i++)
        {
            if (strcasecmp(wordlist[i], word) == 0)
            {
                ids = (const unsigned char*)(wordlist[i] + strlen(wordlist[i]) + 1);
                return;
            }
        }
    }
    else if (isalpha(word[0]))
    {
        if (en_dict.find(first_char) == en_dict.end())
            return;

        const std::vector<const char*>& wordlist = en_dict.at(first_char);
        for (size_t i = 0; i < wordlist.size(); i++)
        {
            if (strcasecmp(wordlist[i], word) == 0)
            {
                ids = (const unsigned char*)(wordlist[i] + strlen(wordlist[i]) + 1);
                return;
            }
        }
    }
    else
    {
        if (dict.find(first_char) == dict.end())
            return;

        const std::vector<const char*>& wordlist = dict.at(first_char);
        for (size_t i = 0; i < wordlist.size(); i++)
        {
            if (strcasecmp(wordlist[i], word) == 0)
            {
                ids = (const unsigned char*)(wordlist[i] + strlen(wordlist[i]) + 1);
                return;
            }
        }
    }
}

static bool is_word_eos(const char* word)
{
    if (((const unsigned char*)word)[0] < 128)
    {
        const char c = word[0];
        return c == ',' || c == '.' || c == ';' || c == '?' || c == '!';
    }

    return strcmp(word, "\xef\xbc\x8c") == 0  // ，
        || strcmp(word, "\xe3\x80\x82") == 0   // 。
        || strcmp(word, "\xe3\x80\x81") == 0   // 、
        || strcmp(word, "\xef\xbc\x9b") == 0   // ；
        || strcmp(word, "\xef\xbc\x9a") == 0   // ：
        || strcmp(word, "\xef\xbc\x9f") == 0   // ？
        || strcmp(word, "\xef\xbc\x81") == 0;  // ！
}

void SimpleG2P::phonemize(const char* text, std::vector<int>& sequence_ids) const
{
    const int ID_PAD = 0;
    const int ID_BOS = 1;
    const int ID_EOS = 2;
    const int ID_SPACE = 3;

    bool last_char_is_control = false;
    bool sentence_begin = true;
    bool sentence_end = true;

    char word[256];

    const char* p = text;
    while (*p)
    {
        if (sentence_end && !last_char_is_control)
        {
            sequence_ids.push_back(ID_BOS);
            sequence_ids.push_back(ID_PAD);
            sentence_end = false;
        }

        if (sentence_begin || last_char_is_control)
        {
            // the very first word
        }
        else
        {
            sequence_ids.push_back(ID_SPACE);
            sequence_ids.push_back(ID_PAD);
        }

        if (isalnum((unsigned char)*p))
        {
            char* pword = word;
            *pword++ = *p++;
            int wordlen = 1;
            while (isalnum((unsigned char)*p) && wordlen < 233)
            {
                *pword++ = *p++;
                wordlen++;
            }
            *pword = '\0';

            if (is_word_eos(word))
            {
                if (!sentence_end)
                    sequence_ids.push_back(ID_EOS);
                sentence_end = true;
                last_char_is_control = false;
                sentence_begin = false;
                continue;
            }

            const unsigned char* ids = 0;
            this->find(word, ids);
            if (ids)
            {
                const unsigned char* pids = ids;
                while (*pids != 0xff)
                {
                    sequence_ids.push_back(*pids);
                    sequence_ids.push_back(ID_PAD);
                    pids++;
                }
            }
            else
            {
                // no such word, spell alphabet one by one
                char tmp[2] = {'\0', '\0'};
                for (size_t i = 0; i < strlen(word); i++)
                {
                    tmp[0] = word[i];
                    this->find(tmp, ids);
                    if (ids)
                    {
                        const unsigned char* pids = ids;
                        while (*pids != 0xff)
                        {
                            sequence_ids.push_back(*pids);
                            sequence_ids.push_back(ID_PAD);
                            pids++;
                        }
                        if (i + 1 != strlen(word))
                        {
                            sequence_ids.push_back(ID_SPACE);
                            sequence_ids.push_back(ID_PAD);
                        }
                    }
                }
            }

            last_char_is_control = false;
            sentence_begin = false;
            continue;
        }

        int len = get_char_width(p);
        if (len > 1)
        {
            char* pword = word;
            int wordlen = 0;

            for (int i = 0; i < len; i++)
            {
                *pword++ = *p++;
                wordlen++;
            }
            *pword = '\0';

            if (is_word_eos(word))
            {
                if (!sentence_end)
                    sequence_ids.push_back(ID_EOS);
                sentence_end = true;
                last_char_is_control = false;
                sentence_begin = false;
                continue;
            }

            const unsigned char* ids = 0;
            this->find(word, ids);
            while (ids && wordlen < 233)
            {
                char* pword0 = pword;
                const char* p0 = p;

                len = get_char_width(p);
                if (len > 1)
                {
                    for (int i = 0; i < len; i++)
                    {
                        *pword++ = *p++;
                        wordlen++;
                    }
                    *pword = '\0';
                }
                else
                {
                    break;
                }

                const unsigned char* ids2 = 0;
                this->find(word, ids2);
                if (ids2)
                {
                    ids = ids2;
                }
                else
                {
                    *pword0 = '\0';
                    p = p0;
                    break;
                }
            }

            if (ids)
            {
                const unsigned char* pids = ids;
                while (*pids != 0xff)
                {
                    sequence_ids.push_back(*pids);
                    sequence_ids.push_back(ID_PAD);
                    pids++;
                }
                sentence_begin = false;
                last_char_is_control = false;
            }
        }
        else
        {
            // skip control character
            p++;
            last_char_is_control = true;
        }
    }

    if (!sentence_end)
        sequence_ids.push_back(ID_EOS);
}

int SimpleG2P::get_char_width(const char* pchar) const
{
    unsigned char c = ((const unsigned char*)pchar)[0];
    if (c < 128)
        return 1;
    if ((c & 0xe0) == 0xc0)
        return 2;
    if ((c & 0xf0) == 0xe0)
        return 3;
    if ((c & 0xf8) == 0xf0)
        return 4;
    return 1;
}

unsigned int SimpleG2P::get_first_char(const char* word) const
{
    const unsigned char* pword = (const unsigned char*)word;
    unsigned int c = pword[0];
    if (c >= 128)
    {
        if ((c & 0xe0) == 0xc0)
            c = (pword[0] << 8) | pword[1];
        else if ((c & 0xf0) == 0xe0)
            c = (pword[0] << 16) | (pword[1] << 8) | pword[2];
        else if ((c & 0xf8) == 0xf0)
            c = (pword[0] << 24) | (pword[1] << 16) | (pword[2] << 8) | pword[3];
    }
    else
    {
        c = toupper((unsigned char)word[0]);
    }
    return c;
}
