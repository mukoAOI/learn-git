#include <stddef.h>

#include <ft2build.h>
#include FT_FREETYPE_H
#include <GL/gl.h>

#include "freetype_text.h"

static FT_Library g_ft_lib = NULL;
static FT_Face g_ft_face = NULL;
static GLuint g_text_tex = 0;

static int utf8_next(const unsigned char *s, int len, int *i, unsigned int *out_cp) {
    if (*i >= len) return 0;

    unsigned char b0 = s[*i];
    if (b0 < 0x80) {
        *out_cp = b0;
        *i += 1;
        return 1;
    }
    if ((b0 & 0xE0) == 0xC0) {
        if (*i + 1 >= len) return 0;
        unsigned char b1 = s[*i + 1];
        if ((b1 & 0xC0) != 0x80) return 0;
        *out_cp = ((unsigned int)(b0 & 0x1F) << 6) | (unsigned int)(b1 & 0x3F);
        *i += 2;
        return 1;
    }
    if ((b0 & 0xF0) == 0xE0) {
        if (*i + 2 >= len) return 0;
        unsigned char b1 = s[*i + 1];
        unsigned char b2 = s[*i + 2];
        if ((b1 & 0xC0) != 0x80 || (b2 & 0xC0) != 0x80) return 0;
        *out_cp =
            ((unsigned int)(b0 & 0x0F) << 12) |
            ((unsigned int)(b1 & 0x3F) << 6) |
            (unsigned int)(b2 & 0x3F);
        *i += 3;
        return 1;
    }
    if ((b0 & 0xF8) == 0xF0) {
        if (*i + 3 >= len) return 0;
        unsigned char b1 = s[*i + 1];
        unsigned char b2 = s[*i + 2];
        unsigned char b3 = s[*i + 3];
        if ((b1 & 0xC0) != 0x80 || (b2 & 0xC0) != 0x80 || (b3 & 0xC0) != 0x80) return 0;
        *out_cp =
            ((unsigned int)(b0 & 0x07) << 18) |
            ((unsigned int)(b1 & 0x3F) << 12) |
            ((unsigned int)(b2 & 0x3F) << 6) |
            (unsigned int)(b3 & 0x3F);
        *i += 4;
        return 1;
    }
    return 0;
}

int ft_text_init(const char *font_path, int pixel_height) {
    if (!font_path || pixel_height <= 0) return 0;
    if (FT_Init_FreeType(&g_ft_lib) != 0) return 0;
    if (FT_New_Face(g_ft_lib, font_path, 0, &g_ft_face) != 0) return 0;
    if (FT_Set_Pixel_Sizes(g_ft_face, 0, (FT_UInt)pixel_height) != 0) return 0;

    glGenTextures(1, &g_text_tex);
    glBindTexture(GL_TEXTURE_2D, g_text_tex);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    return 1;
}

void ft_text_deinit(void) {
    if (g_text_tex != 0) {
        glDeleteTextures(1, &g_text_tex);
        g_text_tex = 0;
    }
    if (g_ft_face) {
        FT_Done_Face(g_ft_face);
        g_ft_face = NULL;
    }
    if (g_ft_lib) {
        FT_Done_FreeType(g_ft_lib);
        g_ft_lib = NULL;
    }
}

void ft_draw_text(float x, float y, const unsigned char *text, int text_len, float scale, float r, float g, float b, float a) {
    if (!g_ft_face || !text || text_len <= 0) return;

    float pen_x = x;
    int max_top = 0;

    for (int i = 0; i < text_len;) {
        unsigned int cp = 0;
        if (!utf8_next(text, text_len, &i, &cp)) break;
        if (cp == ' ') continue;
        if (FT_Load_Char(g_ft_face, cp, FT_LOAD_RENDER) != 0) continue;
        if (g_ft_face->glyph->bitmap_top > max_top) {
            max_top = g_ft_face->glyph->bitmap_top;
        }
    }

    glEnable(GL_TEXTURE_2D);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glColor4f(r, g, b, a);
    glBindTexture(GL_TEXTURE_2D, g_text_tex);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);

    for (int i = 0; i < text_len;) {
        unsigned int cp = 0;
        if (!utf8_next(text, text_len, &i, &cp)) break;
        if (cp == ' ') {
            pen_x += 6.0f * scale;
            continue;
        }

        if (FT_Load_Char(g_ft_face, cp, FT_LOAD_RENDER) != 0) {
            pen_x += 8.0f * scale;
            continue;
        }

        FT_GlyphSlot glyph = g_ft_face->glyph;
        const int bw = (int)glyph->bitmap.width;
        const int bh = (int)glyph->bitmap.rows;

        if (bw > 0 && bh > 0 && glyph->bitmap.buffer) {
            // FreeType bitmap rows may have pitch != width. Build tight buffer.
            unsigned char tight[4096];
            unsigned char *buffer = glyph->bitmap.buffer;
            const int pitch = (int)glyph->bitmap.pitch;
            const int abs_pitch = pitch < 0 ? -pitch : pitch;
            if (bw * bh > (int)sizeof(tight)) {
                continue;
            }
            for (int row = 0; row < bh; ++row) {
                const int src_row = pitch < 0 ? (bh - 1 - row) : row;
                const unsigned char *src = buffer + src_row * abs_pitch;
                unsigned char *dst = tight + row * bw;
                for (int col = 0; col < bw; ++col) {
                    dst[col] = src[col];
                }
            }

            glTexImage2D(
                GL_TEXTURE_2D,
                0,
                GL_ALPHA,
                bw,
                bh,
                0,
                GL_ALPHA,
                GL_UNSIGNED_BYTE,
                tight
            );

            const float xpos = pen_x + (float)glyph->bitmap_left * scale;
            const float ypos = y + ((float)max_top - (float)glyph->bitmap_top) * scale;
            const float w = (float)bw * scale;
            const float h = (float)bh * scale;

            glBegin(GL_QUADS);
            glTexCoord2f(0.0f, 0.0f); glVertex2f(xpos, ypos);
            glTexCoord2f(1.0f, 0.0f); glVertex2f(xpos + w, ypos);
            glTexCoord2f(1.0f, 1.0f); glVertex2f(xpos + w, ypos + h);
            glTexCoord2f(0.0f, 1.0f); glVertex2f(xpos, ypos + h);
            glEnd();
        }

        pen_x += (float)(glyph->advance.x >> 6) * scale;
    }

    glDisable(GL_TEXTURE_2D);
}
