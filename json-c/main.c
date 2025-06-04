#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <math.h>

// ==============================
// 1. ����JSON���ݽṹ
// ==============================
typedef enum {
    JSON_NULL,
    JSON_BOOL,
    JSON_NUMBER,
    JSON_STRING,
    JSON_ARRAY,
    JSON_OBJECT
} JsonType;

typedef struct JsonValue JsonValue;
typedef struct JsonMember JsonMember;

struct JsonValue {
    JsonType type;
    union {
        int boolean;       // ����ֵ
        double number;     // ����
        char* string;      // �ַ���
        struct {           // ����
            JsonValue* values;
            size_t count;
        } array;
        struct {           // ����
            JsonMember* members;
            size_t count;
        } object;
    } value;
};

struct JsonMember {
    char* key;
    JsonValue value;
};

// ==============================
// 2. �ʷ������� (Lexer)
// ==============================
typedef struct {
    const char* json;
    size_t pos;
} Lexer;

// �����հ��ַ�
static void skip_whitespace(Lexer* lexer) {
    while (isspace(lexer->json[lexer->pos])) lexer->pos++;
}

// �����ַ��� (����ת���ַ�)
static char* parse_string(Lexer* lexer) {
    lexer->pos++; // ������ʼ����"
    size_t start = lexer->pos;
    size_t len = 0;

    while (lexer->json[lexer->pos] != '"') {
        if (lexer->json[lexer->pos] == '\\') lexer->pos++; // ����ת���ַ�
        lexer->pos++;
        len++;
    }

    char* str = malloc(len + 1);
    size_t i = 0;
    lexer->pos = start;

    while (lexer->json[lexer->pos] != '"') {
        if (lexer->json[lexer->pos] == '\\') {
            lexer->pos++;
            switch (lexer->json[lexer->pos]) {
                case '"':  str[i] = '"';  break;
                case '\\': str[i] = '\\'; break;
                case '/':  str[i] = '/';  break;
                case 'b':  str[i] = '\b'; break;
                case 'f':  str[i] = '\f'; break;
                case 'n':  str[i] = '\n'; break;
                case 'r':  str[i] = '\r'; break;
                case 't':  str[i] = '\t'; break;
                default: str[i] = lexer->json[lexer->pos]; // ��������ת��
            }
        } else {
            str[i] = lexer->json[lexer->pos];
        }
        i++;
        lexer->pos++;
    }

    str[i] = '\0';
    lexer->pos++; // ������������"
    return str;
}

// ��������
static double parse_number(Lexer* lexer) {
    char* end;
    double num = strtod(lexer->json + lexer->pos, &end);
    lexer->pos = end - lexer->json;
    return num;
}

// ��ȡ��һ��Token
static int lex_next(Lexer* lexer, JsonValue* value) {
    skip_whitespace(lexer);
    char c = lexer->json[lexer->pos];

    switch (c) {
        case '\0': return 0; // ����
        case '{': case '}': case '[': case ']': case ':': case ',':
            lexer->pos++;
            return c; // ���ر�����

        case '"': // �ַ���
            value->type = JSON_STRING;
            value->value.string = parse_string(lexer);
            return 's'; // �Զ�����

        case 't': // true
            if (strncmp(lexer->json + lexer->pos, "true", 4) == 0) {
                lexer->pos += 4;
                value->type = JSON_BOOL;
                value->value.boolean = 1;
                return 'b';
            }
            break;

        case 'f': // false
            if (strncmp(lexer->json + lexer->pos, "false", 5) == 0) {
                lexer->pos += 5;
                value->type = JSON_BOOL;
                value->value.boolean = 0;
                return 'b';
            }
            break;

        case 'n': // null
            if (strncmp(lexer->json + lexer->pos, "null", 4) == 0) {
                lexer->pos += 4;
                value->type = JSON_NULL;
                return 'n';
            }
            break;

        default: // ����
            if (c == '-' || isdigit(c)) {
                value->type = JSON_NUMBER;
                value->value.number = parse_number(lexer);
                return 'd'; // �Զ�����
            }
    }

    return -1; // ����
}

// ==============================
// 3. �﷨������ (Parser)
// ==============================
static JsonValue parse_value(Lexer* lexer);
static JsonValue parse_array(Lexer* lexer);
static JsonValue parse_object(Lexer* lexer);

// ����ֵ
static JsonValue parse_value(Lexer* lexer) {
    JsonValue value;
    int token = lex_next(lexer, &value);

    if (token == 's' || token == 'b' || token == 'd' || token == 'n') {
        return value;
    } else if (token == '[') {
        return parse_array(lexer);
    } else if (token == '{') {
        return parse_object(lexer);
    } else {
        // ������
        value.type = JSON_NULL;
        return value;
    }
}

// ��������
static JsonValue parse_array(Lexer* lexer) {
    JsonValue arr = { .type = JSON_ARRAY, .value.array.count = 0, .value.array.values = NULL };
    size_t capacity = 10;
    arr.value.array.values = malloc(capacity * sizeof(JsonValue));

    if (lexer->json[lexer->pos] == ']') {
        lexer->pos++;
        return arr;
    }

    while (1) {
        // ��������Ԫ��
        JsonValue element = parse_value(lexer);

        // ���ݼ��
        if (arr.value.array.count >= capacity) {
            capacity *= 2;
            arr.value.array.values = realloc(arr.value.array.values, capacity * sizeof(JsonValue));
        }

        arr.value.array.values[arr.value.array.count++] = element;

        // ��鶺�Ż������
        skip_whitespace(lexer);
        if (lexer->json[lexer->pos] == ',') {
            lexer->pos++;
        } else if (lexer->json[lexer->pos] == ']') {
            lexer->pos++;
            break;
        } else {
            // ������
            break;
        }
    }

    return arr;
}

// ��������
static JsonValue parse_object(Lexer* lexer) {
    JsonValue obj = { .type = JSON_OBJECT, .value.object.count = 0, .value.object.members = NULL };
    size_t capacity = 10;
    obj.value.object.members = malloc(capacity * sizeof(JsonMember));

    if (lexer->json[lexer->pos] == '}') {
        lexer->pos++;
        return obj;
    }

    while (1) {
        // ������
        skip_whitespace(lexer);
        if (lexer->json[lexer->pos] != '"') break;
        JsonValue key_val;
        lex_next(lexer, &key_val); // ȷ��key���ַ���
        char* key = key_val.value.string;

        // ����ð��
        skip_whitespace(lexer);
        if (lexer->json[lexer->pos] != ':') break;
        lexer->pos++;

        // ����ֵ
        JsonValue val = parse_value(lexer);

        // ���ݼ��
        if (obj.value.object.count >= capacity) {
            capacity *= 2;
            obj.value.object.members = realloc(obj.value.object.members, capacity * sizeof(JsonMember));
        }

        // �������
        obj.value.object.members[obj.value.object.count].key = key;
        obj.value.object.members[obj.value.object.count].value = val;
        obj.value.object.count++;

        // ��鶺�Ż������
        skip_whitespace(lexer);
        if (lexer->json[lexer->pos] == ',') {
            lexer->pos++;
        } else if (lexer->json[lexer->pos] == '}') {
            lexer->pos++;
            break;
        } else {
            break; // ����
        }
    }

    return obj;
}

// ==============================
// 4. ������ں���
// ==============================
JsonValue json_parse(const char* json_str) {
    Lexer lexer = { .json = json_str, .pos = 0 };
    return parse_value(&lexer);
}

// ==============================
// 5. �ڴ��ͷź���
// ==============================
void json_free(JsonValue* value) {
    switch (value->type) {
        case JSON_STRING:
            free(value->value.string);
            break;
        case JSON_ARRAY:
            for (size_t i = 0; i < value->value.array.count; i++) {
                json_free(&value->value.array.values[i]);
            }
            free(value->value.array.values);
            break;
        case JSON_OBJECT:
            for (size_t i = 0; i < value->value.object.count; i++) {
                free(value->value.object.members[i].key);
                json_free(&value->value.object.members[i].value);
            }
            free(value->value.object.members);
            break;
        default:
            break; // �������������ͷ�
    }
}

// ==============================
// 6. ��ӡJSON (���ڵ���)
// ==============================
void json_print(const JsonValue* value, int indent) {
    switch (value->type) {
        case JSON_NULL:
            printf("null");
            break;
        case JSON_BOOL:
            printf(value->value.boolean ? "true" : "false");
            break;
        case JSON_NUMBER:
            printf("%.15g", value->value.number);
            break;
        case JSON_STRING:
            printf("\"%s\"", value->value.string);
            break;
        case JSON_ARRAY:
            printf("[\n");
            for (size_t i = 0; i < value->value.array.count; i++) {
                for (int j = 0; j < indent + 2; j++) printf(" ");
                json_print(&value->value.array.values[i], indent + 2);
                if (i < value->value.array.count - 1) printf(",");
                printf("\n");
            }
            for (int i = 0; i < indent; i++) printf(" ");
            printf("]");
            break;
        case JSON_OBJECT:
            printf("{\n");
            for (size_t i = 0; i < value->value.object.count; i++) {
                for (int j = 0; j < indent + 2; j++) printf(" ");
                printf("\"%s\": ", value->value.object.members[i].key);
                json_print(&value->value.object.members[i].value, indent + 2);
                if (i < value->value.object.count - 1) printf(",");
                printf("\n");
            }
            for (int i = 0; i < indent; i++) printf(" ");
            printf("}");
            break;
    }
}

// ==============================
// 7. ���Դ���
// ==============================
int main() {
    auto a =100;
    const char* json =
        "{"
        "   \"name\": \"Alice\","
        "   \"age\": 30,"
        "   \"scores\": [90, 85, 95],"
        "   \"is_student\": false"
        "}";

    JsonValue parsed = json_parse(json);
    printf("Parsed JSON:\n");
    json_print(&parsed, 0);
    json_free(&parsed);

    return 0;
}