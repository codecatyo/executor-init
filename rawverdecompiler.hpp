#pragma once

#include <vector>
#include <string>
#include <memory>
#include <unordered_map>
#include <unordered_set>
#include <map>
#include <set>
#include <optional>
#include <stack>
#include <sstream>
#include <algorithm>
#include <cstdint>
#include <cstring>
#include <cmath>

namespace Luau {

    //op code ezzz add more ezzz
    enum class OpCode : uint8_t {
        LOP_NOP = 0, LOP_BREAK, LOP_LOADNIL, LOP_LOADB, LOP_LOADN, LOP_LOADK, LOP_MOVE,
        LOP_GETGLOBAL, LOP_SETGLOBAL, LOP_GETUPVAL, LOP_SETUPVAL, LOP_CLOSEUPVALS,
        LOP_GETIMPORT, LOP_GETTABLE, LOP_SETTABLE, LOP_GETTABLEKS, LOP_SETTABLEKS,
        LOP_GETTABLEN, LOP_SETTABLEN, LOP_NEWCLOSURE, LOP_NAMECALL, LOP_CALL,
        LOP_RETURN, LOP_JUMP, LOP_JUMPBACK, LOP_JUMPIF, LOP_JUMPIFNOT,
        LOP_JUMPIFEQ, LOP_JUMPIFLE, LOP_JUMPIFLT, LOP_JUMPIFNOTEQ, LOP_JUMPIFNOTLE, LOP_JUMPIFNOTLT,
        LOP_ADD, LOP_SUB, LOP_MUL, LOP_DIV, LOP_MOD, LOP_POW,
        LOP_ADDK, LOP_SUBK, LOP_MULK, LOP_DIVK, LOP_MODK, LOP_POWK,
        LOP_AND, LOP_OR, LOP_ANDK, LOP_ORK, LOP_CONCAT, LOP_NOT, LOP_MINUS, LOP_LENGTH,
        LOP_NEWTABLE, LOP_DUPTABLE, LOP_SETLIST, LOP_FORNPREP, LOP_FORNLOOP, LOP_FORGLOOP,
        LOP_FORGPREP_INEXT, LOP_FORGLOOP_INEXT, LOP_FORGPREP_NEXT, LOP_FORGLOOP_NEXT,
        LOP_GETVARARGS, LOP_DUPCLOSURE, LOP_PREPVARARGS, LOP_LOADKX, LOP_JUMPX,
        LOP_FASTCALL, LOP_COVERAGE, LOP_CAPTURE, LOP_JUMPIFEQK, LOP_JUMPIFNOTEQK,
        LOP_FASTCALL1, LOP_FASTCALL2, LOP_FASTCALL2K, LOP_FORGPREP, LOP_IDIV
    };

    struct Instruction {
        OpCode op;
        uint8_t a, b, c;
        int16_t d;
        int32_t e;
        uint32_t aux;
        uint32_t raw;

        static Instruction parse(uint32_t insn) {
            Instruction i;
            i.raw = insn;
            i.op = static_cast<OpCode>(insn & 0xFF);
            i.a = (insn >> 8) & 0xFF;
            i.b = (insn >> 16) & 0xFF;
            i.c = (insn >> 24) & 0xFF;
            i.d = static_cast<int16_t>((insn >> 16) & 0xFFFF);
            i.e = static_cast<int32_t>(insn >> 8);
            i.aux = 0;
            return i;
        }
    };



    struct Expr {
        enum class Type { Literal, Variable, Unary, Binary, Call, Index, Table, Closure };
        Type type;
        int priority = 0;
        virtual std::string to_string() const = 0;
        virtual ~Expr() = default;
    };
    using ExprPtr = std::shared_ptr<Expr>;

    struct LiteralExpr : Expr {
        std::string value;
        LiteralExpr(const std::string& v) : value(v) { type = Type::Literal; priority = 10; }
        std::string to_string() const override { return value; }
    };

    struct VarExpr : Expr {
        std::string name;
        VarExpr(const std::string& n) : name(n) { type = Type::Variable; priority = 10; }
        std::string to_string() const override { return name; }
    };

    struct UnaryExpr : Expr {
        std::string op;
        ExprPtr operand;
        UnaryExpr(const std::string& o, ExprPtr opnd, int p)
            : op(o), operand(std::move(opnd)) {
            type = Type::Unary;
            priority = p;
        }
        std::string to_string() const override {
            std::string opr = (operand->priority < priority) ? "(" + operand->to_string() + ")" : operand->to_string();
            return op + " " + opr;
        }
    };

    struct BinaryExpr : Expr {
        std::string op;
        ExprPtr left, right;
        bool left_assoc;
        BinaryExpr(const std::string& o, ExprPtr l, ExprPtr r, int p, bool assoc = true)
            : op(o), left(std::move(l)), right(std::move(r)), left_assoc(assoc) {
            type = Type::Binary;
            priority = p;
        }
        std::string to_string() const override {
            std::string lstr = left->to_string();
            if (left->priority < priority) lstr = "(" + lstr + ")";
            else if (left->priority == priority && !left_assoc) lstr = "(" + lstr + ")";

            std::string rstr = right->to_string();
            if (right->priority < priority) rstr = "(" + rstr + ")";
            else if (right->priority == priority && left_assoc) rstr = "(" + rstr + ")";

            return lstr + " " + op + " " + rstr;
        }
    };

    struct CallExpr : Expr {
        ExprPtr func;
        std::vector<ExprPtr> args;
        bool is_method = false; 
        std::string method_name;  
        CallExpr(ExprPtr f, std::vector<ExprPtr> a) : func(std::move(f)), args(std::move(a)) {
            type = Type::Call;
            priority = 10;
        }
        std::string to_string() const override {
            if (is_method) {
                std::string obj = func->to_string();
                std::string res = obj + ":" + method_name + "(";
                for (size_t i = 0; i < args.size(); ++i)
                    res += (i == 0 ? "" : ", ") + args[i]->to_string();
                return res + ")";
            }
            else {
                std::string res = func->to_string() + "(";
                for (size_t i = 0; i < args.size(); ++i)
                    res += (i == 0 ? "" : ", ") + args[i]->to_string();
                return res + ")";
            }
        }
    };

    struct IndexExpr : Expr {
        ExprPtr object;
        ExprPtr index;
        IndexExpr(ExprPtr obj, ExprPtr idx) : object(std::move(obj)), index(std::move(idx)) {
            type = Type::Index;
            priority = 10;
        }
        std::string to_string() const override {
            if (index->type == Expr::Type::Literal) {
                auto lit = std::static_pointer_cast<LiteralExpr>(index);
                if (lit->value.size() >= 2 && lit->value.front() == '"' && lit->value.back() == '"') {
                    std::string s = lit->value.substr(1, lit->value.size() - 2);
                    bool valid = !s.empty() && (isalpha(s[0]) || s[0] == '_');
                    for (char c : s) if (!isalnum(c) && c != '_') valid = false;
                    if (valid) return object->to_string() + "." + s;
                }
            }
            return object->to_string() + "[" + index->to_string() + "]";
        }
    };

    struct TableExpr : Expr {
        std::vector<std::pair<ExprPtr, ExprPtr>> fields; // (key, value); key == nullptr for 
        TableExpr() { type = Type::Table; priority = 10; }
        std::string to_string() const override {
            std::string res = "{";
            for (size_t i = 0; i < fields.size(); ++i) {
                if (i > 0) res += ", ";
                if (!fields[i].first) {
                    res += fields[i].second->to_string();
                }
                else {
                    res += fields[i].first->to_string() + " = " + fields[i].second->to_string();
                }
            }
            return res + "}";
        }
    };

    struct ClosureExpr : Expr {
        int proto_id;
        std::shared_ptr<std::string> cached_code;  // 
        ClosureExpr(int pid) : proto_id(pid) { type = Type::Closure; priority = 10; }
        std::string to_string() const override {
            if (cached_code) return *cached_code;
            return "function(...) --[[closure " + std::to_string(proto_id) + "]] end";
        }
    };



    struct Statement {
        enum class Type { Assign, If, While, Repeat, Return, Call, Break, ForNumeric, ForGeneric };
        Type type;
        virtual std::string to_string(int indent) const = 0;
        virtual ~Statement() = default;
    };
    using StmtPtr = std::shared_ptr<Statement>;

    struct Block {
        std::vector<StmtPtr> statements;
        std::string to_string(int indent) const {
            std::string res;
            for (auto& stmt : statements) res += stmt->to_string(indent) + "\n";
            return res;
        }
    };

    struct AssignStmt : Statement {
        ExprPtr target;
        ExprPtr value;
        AssignStmt(ExprPtr t, ExprPtr v) : target(std::move(t)), value(std::move(v)) { type = Type::Assign; }
        std::string to_string(int indent) const override {
            return std::string(indent * 2, ' ') + target->to_string() + " = " + value->to_string();
        }
    };

    struct ReturnStmt : Statement {
        std::vector<ExprPtr> values;
        ReturnStmt(std::vector<ExprPtr> v) : values(std::move(v)) { type = Type::Return; }
        std::string to_string(int indent) const override {
            std::string res = std::string(indent * 2, ' ') + "return ";
            for (size_t i = 0; i < values.size(); ++i)
                res += (i == 0 ? "" : ", ") + values[i]->to_string();
            return res;
        }
    };

    struct IfStmt : Statement {
        ExprPtr condition;
        std::shared_ptr<Block> then_block;
        std::shared_ptr<Block> else_block;
        std::vector<std::shared_ptr<IfStmt>> elseif_chain;
        IfStmt(ExprPtr cond) : condition(std::move(cond)) {
            type = Type::If;
            then_block = std::make_shared<Block>();
        }
        std::string to_string(int indent) const override {
            std::string pad(indent * 2, ' ');
            std::string res = pad + "if " + condition->to_string() + " then\n";
            res += then_block->to_string(indent + 1);
            for (auto& eif : elseif_chain) {
                res += pad + "elseif " + eif->condition->to_string() + " then\n";
                res += eif->then_block->to_string(indent + 1);
            }
            if (else_block) {
                res += pad + "else\n";
                res += else_block->to_string(indent + 1);
            }
            res += pad + "end";
            return res;
        }
    };

    struct WhileStmt : Statement {
        ExprPtr condition;
        std::shared_ptr<Block> body;
        WhileStmt(ExprPtr cond) : condition(std::move(cond)) {
            type = Type::While;
            body = std::make_shared<Block>();
        }
        std::string to_string(int indent) const override {
            std::string pad(indent * 2, ' ');
            std::string res = pad + "while " + condition->to_string() + " do\n";
            res += body->to_string(indent + 1);
            res += pad + "end";
            return res;
        }
    };

    struct RepeatStmt : Statement {
        ExprPtr condition;
        std::shared_ptr<Block> body;
        RepeatStmt(ExprPtr cond) : condition(std::move(cond)) {
            type = Type::Repeat;
            body = std::make_shared<Block>();
        }
        std::string to_string(int indent) const override {
            std::string pad(indent * 2, ' ');
            std::string res = pad + "repeat\n";
            res += body->to_string(indent + 1);
            res += pad + "until " + condition->to_string();
            return res;
        }
    };

    struct BreakStmt : Statement {
        BreakStmt() { type = Type::Break; }
        std::string to_string(int indent) const override {
            return std::string(indent * 2, ' ') + "break";
        }
    };

    struct ForNumericStmt : Statement {
        std::string var;
        ExprPtr start, end, step;
        std::shared_ptr<Block> body;
        ForNumericStmt() { type = Type::ForNumeric; }
        std::string to_string(int indent) const override {
            std::string pad(indent * 2, ' ');
            std::string res = pad + "for " + var + " = " + start->to_string() + ", " + end->to_string();
            if (step) res += ", " + step->to_string();
            res += " do\n";
            res += body->to_string(indent + 1);
            res += pad + "end";
            return res;
        }
    };

    struct ForGenericStmt : Statement {
        std::vector<std::string> vars;
        std::vector<ExprPtr> generators;
        std::shared_ptr<Block> body;
        ForGenericStmt() { type = Type::ForGeneric; }
        std::string to_string(int indent) const override {
            std::string pad(indent * 2, ' ');
            std::string res = pad + "for ";
            for (size_t i = 0; i < vars.size(); ++i) {
                if (i > 0) res += ", ";
                res += vars[i];
            }
            res += " in ";
            for (size_t i = 0; i < generators.size(); ++i) {
                if (i > 0) res += ", ";
                res += generators[i]->to_string();
            }
            res += " do\n";
            res += body->to_string(indent + 1);
            res += pad + "end";
            return res;
        }
    };



    class Decompiler {
    public:
        std::string decompile(const std::vector<uint8_t>& bytecode) {
            try {
                parse_bytecode(bytecode);
                return reconstruct();
            }
            catch (const std::exception& e) {
                return "-- Error: " + std::string(e.what());
            }
        }

    private:
        struct ProtoData {
            uint8_t num_params;
            bool is_vararg;
            std::vector<Instruction> instructions;
            std::vector<std::string> constants;
            std::vector<int> child_protos;
            std::vector<std::string> upvalue_names;
            int stack_size;
            std::string name;
        };
        std::vector<ProtoData> protos;
        int main_proto;

        size_t offset = 0;
        const uint8_t* data = nullptr;
        size_t data_size = 0;

        void parse_bytecode(const std::vector<uint8_t>& bytecode) {
            data = bytecode.data();
            data_size = bytecode.size();
            offset = 0;

            uint8_t version = read_u8();
            if (version >= 4) read_u8();  // skip ezz

            // string table
            size_t str_count = read_leb128();
            std::vector<std::string> strings;
            for (size_t i = 0; i < str_count; ++i) {
                size_t len = read_leb128();
                strings.push_back(std::string((const char*)data + offset, len));
                offset += len;
            }

            // prototypes
            size_t proto_count = read_leb128();
            protos.resize(proto_count);
            for (size_t i = 0; i < proto_count; ++i) {
                ProtoData p;
                // source name index (string)
                read_leb128();
                p.num_params = read_u8();
                p.is_vararg = read_u8() != 0;
                p.stack_size = read_u8();
                // code size ( i uess bro
                read_leb128();

                // instructions
                size_t ins_count = read_leb128();
                std::vector<uint32_t> raw_ins(ins_count);
                for (size_t j = 0; j < ins_count; ++j) raw_ins[j] = read_u32();
                for (size_t j = 0; j < ins_count; ++j) {
                    Instruction ins = Instruction::parse(raw_ins[j]);
                    if (has_aux(ins.op)) {
                        if (j + 1 < ins_count) {
                            ins.aux = raw_ins[++j];
                        }
                    }
                    p.instructions.push_back(ins);
                }

                // constants
                size_t const_count = read_leb128();
                for (size_t j = 0; j < const_count; ++j) {
                    uint8_t type = read_u8();
                    switch (type) {
                    case 0: p.constants.push_back("nil"); break;
                    case 1: p.constants.push_back(read_u8() ? "true" : "false"); break;
                    case 2: {
                        double d;
                        memcpy(&d, data + offset, 8);
                        offset += 8;
                        std::string s = format_number(d);
                        p.constants.push_back(s);
                        break;
                    }
                    case 3: {
                        size_t idx = read_leb128() - 1;
                        p.constants.push_back("\"" + escape_string(strings[idx]) + "\"");
                        break;
                    }
                    default: p.constants.push_back("nil"); break;
                    }
                }

                // child prototypes
                size_t children = read_leb128();
                for (size_t j = 0; j < children; ++j) {
                    p.child_protos.push_back((int)read_leb128());
                }

                // debug info (skip for simplicity, but nonono corrupting offset
                read_leb128(); // line number info size
                read_leb128(); // line number info (array of leb128)
                // local varieble info
                size_t local_count = read_leb128();
                for (size_t j = 0; j < local_count; ++j) {
                    read_leb128(); // var name index
                    read_leb128(); // start pc
                    read_leb128(); // end pc
                    read_u8();     // register
                }
                // upvalue names
                size_t upval_count = read_leb128();
                for (size_t j = 0; j < upval_count; ++j) {
                    size_t name_idx = read_leb128();
                    if (name_idx > 0 && name_idx - 1 < strings.size())
                        p.upvalue_names.push_back(strings[name_idx - 1]);
                    else
                        p.upvalue_names.push_back("upvalue_" + std::to_string(j));
                }

                protos[i] = std::move(p);
            }

            main_proto = (int)read_leb128();
        }

        uint8_t read_u8() {
            if (offset >= data_size) throw std::runtime_error("Unexpected end of data");
            return data[offset++];
        }
        uint32_t read_u32() {
            if (offset + 4 > data_size) throw std::runtime_error("Unexpected end of data");
            uint32_t v;
            memcpy(&v, data + offset, 4);
            offset += 4;
            return v;
        }
        size_t read_leb128() {
            size_t result = 0, shift = 0;
            while (true) {
                uint8_t b = read_u8();
                result |= (size_t(b & 0x7f) << shift);
                if (!(b & 0x80)) break;
                shift += 7;
            }
            return result;
        }

        bool has_aux(OpCode op) {
            return op == OpCode::LOP_GETGLOBAL || op == OpCode::LOP_SETGLOBAL ||
                op == OpCode::LOP_GETIMPORT || op == OpCode::LOP_GETTABLEKS ||
                op == OpCode::LOP_SETTABLEKS || op == OpCode::LOP_NAMECALL ||
                op == OpCode::LOP_NEWTABLE || op == OpCode::LOP_SETLIST ||
                op == OpCode::LOP_JUMPIFEQK || op == OpCode::LOP_JUMPIFNOTEQK ||
                op == OpCode::LOP_FASTCALL2K;
        }

        static std::string escape_string(const std::string& s) {
            std::string res;
            for (char c : s) {
                switch (c) {
                case '\n': res += "\\n"; break;
                case '\r': res += "\\r"; break;
                case '\t': res += "\\t"; break;
                case '\"': res += "\\\""; break;
                case '\\': res += "\\\\"; break;
                default: res += c; break;
                }
            }
            return res;
        }

        static std::string format_number(double d) {
            if (std::isnan(d)) return "(0/0)";
            if (std::isinf(d)) return d > 0 ? "1/0" : "-1/0";
            std::string s = std::to_string(d);
            s.erase(s.find_last_not_of('0') + 1, std::string::npos);
            if (s.back() == '.') s.pop_back();
            return s;
        }

        std::string reconstruct() {
            return lift_proto(main_proto, 0);
        }

        std::string lift_proto(int id, int indent) {
            ProtoData& p = protos[id];

            struct BasicBlock {
                int start_pc, end_pc;
                int true_target = -1, false_target = -1;
                bool is_cond = false, is_jump = false, is_ret = false;
            };
            std::map<int, BasicBlock> blocks_by_start;
            std::set<int> leaders = { 0 };
            for (size_t i = 0; i < p.instructions.size(); ++i) {
                Instruction& ins = p.instructions[i];
                if (ins.op == OpCode::LOP_JUMP || ins.op == OpCode::LOP_JUMPBACK ||
                    is_cond_jump(ins.op) || ins.op == OpCode::LOP_RETURN) {
                    leaders.insert(i + 1);
                    if (ins.op != OpCode::LOP_RETURN && !is_cond_jump(ins.op))
                        leaders.insert(i + 1 + ins.d);
                    else if (is_cond_jump(ins.op))
                        leaders.insert(i + 1 + ins.d);
                }
            }
            int last = 0;
            for (int pc : leaders) {
                if (pc > (int)p.instructions.size()) continue;
                BasicBlock bb;
                bb.start_pc = last;
                bb.end_pc = pc - 1;
                if (last < (int)p.instructions.size()) {
                    Instruction& last_ins = p.instructions[bb.end_pc];
                    if (is_cond_jump(last_ins.op)) {
                        bb.is_cond = true;
                        bb.true_target = bb.end_pc + 1 + last_ins.d;
                        bb.false_target = bb.end_pc + 1;
                    }
                    else if (last_ins.op == OpCode::LOP_JUMP || last_ins.op == OpCode::LOP_JUMPBACK) {
                        bb.is_jump = true;
                        bb.true_target = bb.end_pc + 1 + last_ins.d;
                    }
                    else if (last_ins.op == OpCode::LOP_RETURN) {
                        bb.is_ret = true;
                    }
                    else {
                        bb.true_target = bb.end_pc + 1;
                    }
                }
                blocks_by_start[last] = bb;
                last = pc;
            }

            int max_reg = 256;
            std::vector<int> reg_version(max_reg, 0);
            std::unordered_map<std::pair<int, int>, ExprPtr, hash_pair> reg_values;
            auto get_reg = [&](int r) -> ExprPtr {
                int ver = reg_version[r];
                auto key = std::make_pair(r, ver);
                auto it = reg_values.find(key);
                if (it != reg_values.end()) return it->second;
                std::string name;
                if (r < p.num_params) name = "arg" + std::to_string(r);
                else if (r >= max_reg) name = "reg" + std::to_string(r);
                else name = "var" + std::to_string(r) + "_" + std::to_string(ver);
                ExprPtr var = std::make_shared<VarExpr>(name);
                reg_values[key] = var;
                return var;
                };
            auto set_reg = [&](int r, ExprPtr val) {
                reg_version[r]++;
                auto key = std::make_pair(r, reg_version[r]);
                reg_values[key] = val;
                return std::make_shared<AssignStmt>(get_reg(r), val);
                };

            auto const_expr = [&](int idx) -> ExprPtr {
                if (idx < 0 || idx >= (int)p.constants.size())
                    return std::make_shared<LiteralExpr>("nil");
                return std::make_shared<LiteralExpr>(p.constants[idx]);
                };

            auto bin_op = [](OpCode op, ExprPtr a, ExprPtr b, int prio, bool assoc = true) -> ExprPtr {
                std::string op_str;
                switch (op) {
                case OpCode::LOP_ADD: case OpCode::LOP_ADDK: op_str = "+"; break;
                case OpCode::LOP_SUB: case OpCode::LOP_SUBK: op_str = "-"; break;
                case OpCode::LOP_MUL: case OpCode::LOP_MULK: op_str = "*"; break;
                case OpCode::LOP_DIV: case OpCode::LOP_DIVK: op_str = "/"; break;
                case OpCode::LOP_MOD: case OpCode::LOP_MODK: op_str = "%"; break;
                case OpCode::LOP_POW: case OpCode::LOP_POWK: op_str = "^"; break;
                case OpCode::LOP_IDIV: op_str = "//"; break;
                case OpCode::LOP_AND: case OpCode::LOP_ANDK: op_str = "and"; prio = 2; assoc = false; break;
                case OpCode::LOP_OR: case OpCode::LOP_ORK: op_str = "or"; prio = 1; assoc = false; break;
                case OpCode::LOP_CONCAT: op_str = ".."; prio = 4; assoc = false; break;
                default: op_str = "?";
                }
                return std::make_shared<BinaryExpr>(op_str, std::move(a), std::move(b), prio, assoc);
                };
            auto un_op = [](OpCode op, ExprPtr a, int prio) -> ExprPtr {
                std::string op_str;
                switch (op) {
                case OpCode::LOP_NOT: op_str = "not"; break;
                case OpCode::LOP_MINUS: op_str = "-"; break;
                case OpCode::LOP_LENGTH: op_str = "#"; break;
                default: op_str = "?";
                }
                return std::make_shared<UnaryExpr>(op_str, std::move(a), prio);
                };

            auto extract_cond = [&](int pc, const Instruction& ins) -> ExprPtr {
                auto cmp = [&](const std::string& op, ExprPtr l, ExprPtr r) {
                    return std::make_shared<BinaryExpr>(op, std::move(l), std::move(r), 3, true);
                    };
                if (ins.op == OpCode::LOP_JUMPIFEQ) return cmp("==", get_reg(ins.a), get_reg(ins.aux));
                if (ins.op == OpCode::LOP_JUMPIFEQK) return cmp("==", get_reg(ins.a), const_expr(ins.aux));
                if (ins.op == OpCode::LOP_JUMPIFNOTEQ) return cmp("~=", get_reg(ins.a), get_reg(ins.aux));
                if (ins.op == OpCode::LOP_JUMPIFNOTEQK) return cmp("~=", get_reg(ins.a), const_expr(ins.aux));
                if (ins.op == OpCode::LOP_JUMPIFLT) return cmp("<", get_reg(ins.a), get_reg(ins.aux));
                if (ins.op == OpCode::LOP_JUMPIFLE) return cmp("<=", get_reg(ins.a), get_reg(ins.aux));
                if (ins.op == OpCode::LOP_JUMPIFNOTLT) return un_op(OpCode::LOP_NOT, cmp("<", get_reg(ins.a), get_reg(ins.aux)), 7);
                if (ins.op == OpCode::LOP_JUMPIFNOTLE) return un_op(OpCode::LOP_NOT, cmp("<=", get_reg(ins.a), get_reg(ins.aux)), 7);
                if (ins.op == OpCode::LOP_JUMPIF) return get_reg(ins.a);
                if (ins.op == OpCode::LOP_JUMPIFNOT) return un_op(OpCode::LOP_NOT, get_reg(ins.a), 7);
                return std::make_shared<VarExpr>("cond_" + std::to_string(pc));
                };

            std::function<std::shared_ptr<Block>(int, int)> build_block = [&](int start_pc, int limit_pc) -> std::shared_ptr<Block> {
                auto block = std::make_shared<Block>();
                int cur = start_pc;
                std::set<int> seen;
                while (cur != -1 && cur < (int)p.instructions.size() && (limit_pc == -1 || cur < limit_pc)) {
                    if (seen.count(cur)) break;
                    seen.insert(cur);
                    auto it = blocks_by_start.find(cur);
                    if (it == blocks_by_start.end()) break;
                    BasicBlock& bb = it->second;

                    for (int i = bb.start_pc; i <= bb.end_pc; ++i) {
                        Instruction& ins = p.instructions[i];

                        if (ins.op == OpCode::LOP_JUMPBACK) {
                            int loop_start = i + 1 + ins.d;
                            int loop_end = i;
                            ExprPtr cond;
                            if (loop_start > 0 && is_cond_jump(p.instructions[loop_start - 1].op))
                                cond = extract_cond(loop_start - 1, p.instructions[loop_start - 1]);
                            else
                                cond = std::make_shared<LiteralExpr>("true");
                            auto while_stmt = std::make_shared<WhileStmt>(cond);
                            while_stmt->body = build_block(loop_start, loop_end + 1);
                            block->statements.push_back(while_stmt);
                            cur = loop_end + 1;
                            goto next_block;
                        }
                        if (ins.op == OpCode::LOP_FORNPREP) {
                            int loop_start = i + 1 + ins.d;
                            auto for_stmt = std::make_shared<ForNumericStmt>();
                            for_stmt->var = "i" + std::to_string(ins.a);
                            for_stmt->start = get_reg(ins.a + 1);
                            for_stmt->end = get_reg(ins.a + 2);
                            if (ins.b > 0) for_stmt->step = get_reg(ins.a + 3);
                            for_stmt->body = build_block(loop_start, i + 1);
                            block->statements.push_back(for_stmt);
                            cur = i + 1;
                            goto next_block;
                        }

                        if (ins.op == OpCode::LOP_FORGPREP) {
                            int loop_start = i + 1 + ins.d;
                            auto for_stmt = std::make_shared<ForGenericStmt>();
                            for (int v = 0; v < ins.b; ++v)
                                for_stmt->vars.push_back("genvar" + std::to_string(ins.a + v));
                            for_stmt->generators.push_back(get_reg(ins.a));
                            for_stmt->body = build_block(loop_start, i + 1);
                            block->statements.push_back(for_stmt);
                            cur = i + 1;
                            goto next_block;
                        }

                        if (ins.op == OpCode::LOP_BREAK) {
                            block->statements.push_back(std::make_shared<BreakStmt>());
                            continue;
                        }
                      
                        switch (ins.op) {
                        case OpCode::LOP_MOVE: {
                            auto val = get_reg(ins.b);
                            block->statements.push_back(set_reg(ins.a, val));
                            break;
                        }
                        case OpCode::LOP_LOADNIL: {
                            auto nil = std::make_shared<LiteralExpr>("nil");
                            block->statements.push_back(set_reg(ins.a, nil));
                            break;
                        }
                        case OpCode::LOP_LOADB: {
                            auto val = std::make_shared<LiteralExpr>(ins.b ? "true" : "false");
                            block->statements.push_back(set_reg(ins.a, val));
                            break;
                        }
                        case OpCode::LOP_LOADN: {
                            auto val = std::make_shared<LiteralExpr>(std::to_string(ins.d));
                            block->statements.push_back(set_reg(ins.a, val));
                            break;
                        }
                        case OpCode::LOP_LOADK:
                        case OpCode::LOP_LOADKX: {
                            int idx = (ins.op == OpCode::LOP_LOADK) ? ins.d : (int)ins.aux;
                            auto val = const_expr(idx);
                            block->statements.push_back(set_reg(ins.a, val));
                            break;
                        }
                        case OpCode::LOP_GETGLOBAL: {
                            auto global = std::make_shared<VarExpr>("_G[" + p.constants[ins.aux] + "]");
                            block->statements.push_back(set_reg(ins.a, global));
                            break;
                        }
                        case OpCode::LOP_SETGLOBAL: {
                            auto target = std::make_shared<VarExpr>("_G[" + p.constants[ins.aux] + "]");
                            block->statements.push_back(std::make_shared<AssignStmt>(target, get_reg(ins.a)));
                            break;
                        }
                        case OpCode::LOP_GETUPVAL: {
                            std::string name = ins.aux < p.upvalue_names.size() ? p.upvalue_names[ins.aux] : "upvalue" + std::to_string(ins.aux);
                            auto upval = std::make_shared<VarExpr>(name);
                            block->statements.push_back(set_reg(ins.a, upval));
                            break;
                        }
                        case OpCode::LOP_SETUPVAL: {
                            std::string name = ins.aux < p.upvalue_names.size() ? p.upvalue_names[ins.aux] : "upvalue" + std::to_string(ins.aux);
                            auto target = std::make_shared<VarExpr>(name);
                            block->statements.push_back(std::make_shared<AssignStmt>(target, get_reg(ins.a)));
                            break;
                        }
                        case OpCode::LOP_GETTABLE: {
                            auto expr = std::make_shared<IndexExpr>(get_reg(ins.b), get_reg(ins.c));
                            block->statements.push_back(set_reg(ins.a, expr));
                            break;
                        }
                        case OpCode::LOP_SETTABLE: {
                            auto target = std::make_shared<IndexExpr>(get_reg(ins.b), get_reg(ins.c));
                            block->statements.push_back(std::make_shared<AssignStmt>(target, get_reg(ins.a)));
                            break;
                        }
                        case OpCode::LOP_GETTABLEKS: {
                            auto key = const_expr(ins.aux);
                            auto expr = std::make_shared<IndexExpr>(get_reg(ins.b), key);
                            block->statements.push_back(set_reg(ins.a, expr));
                            break;
                        }
                        case OpCode::LOP_SETTABLEKS: {
                            auto key = const_expr(ins.aux);
                            auto target = std::make_shared<IndexExpr>(get_reg(ins.b), key);
                            block->statements.push_back(std::make_shared<AssignStmt>(target, get_reg(ins.a)));
                            break;
                        }
                        case OpCode::LOP_ADD: case OpCode::LOP_ADDK:
                        case OpCode::LOP_SUB: case OpCode::LOP_SUBK:
                        case OpCode::LOP_MUL: case OpCode::LOP_MULK:
                        case OpCode::LOP_DIV: case OpCode::LOP_DIVK:
                        case OpCode::LOP_MOD: case OpCode::LOP_MODK:
                        case OpCode::LOP_POW: case OpCode::LOP_POWK:
                        case OpCode::LOP_IDIV: {
                            ExprPtr rhs = (ins.op >= OpCode::LOP_ADDK && ins.op <= OpCode::LOP_POWK) ?
                                const_expr(ins.aux) : get_reg(ins.c);
                            auto expr = bin_op(ins.op, get_reg(ins.b), rhs, 5);
                            block->statements.push_back(set_reg(ins.a, expr));
                            break;
                        }
                        case OpCode::LOP_AND: case OpCode::LOP_ANDK:
                        case OpCode::LOP_OR: case OpCode::LOP_ORK: {
                            ExprPtr rhs = (ins.op == OpCode::LOP_ANDK || ins.op == OpCode::LOP_ORK) ?
                                const_expr(ins.aux) : get_reg(ins.c);
                            int prio = (ins.op == OpCode::LOP_AND || ins.op == OpCode::LOP_ANDK) ? 2 : 1;
                            auto expr = bin_op(ins.op, get_reg(ins.b), rhs, prio, false);
                            block->statements.push_back(set_reg(ins.a, expr));
                            break;
                        }
                        case OpCode::LOP_CONCAT: {
                            auto expr = bin_op(ins.op, get_reg(ins.b), get_reg(ins.c), 4, false);
                            block->statements.push_back(set_reg(ins.a, expr));
                            break;
                        }
                        case OpCode::LOP_NOT:
                        case OpCode::LOP_MINUS:
                        case OpCode::LOP_LENGTH: {
                            auto expr = un_op(ins.op, get_reg(ins.b), 7);
                            block->statements.push_back(set_reg(ins.a, expr));
                            break;
                        }
                        case OpCode::LOP_NEWTABLE: {
                            auto table = std::make_shared<TableExpr>();
                            block->statements.push_back(set_reg(ins.a, table));
                            break;
                        }
                        case OpCode::LOP_SETLIST: {
                            int base_idx = 1;
                            for (int j = 1; j <= ins.b; ++j) {
                                auto idx_expr = std::make_shared<LiteralExpr>(std::to_string(base_idx++));
                                auto target = std::make_shared<IndexExpr>(get_reg(ins.a), idx_expr);
                                auto val = get_reg(ins.a + j);
                                block->statements.push_back(std::make_shared<AssignStmt>(target, val));
                            }
                            break;
                        }
                        case OpCode::LOP_NAMECALL: {
                            auto obj = get_reg(ins.b);
                            std::string method = p.constants[ins.aux];
                            method = method.substr(1, method.size() - 2);
                            auto call_expr = std::make_shared<CallExpr>(obj, std::vector<ExprPtr>());
                            call_expr->is_method = true;
                            call_expr->method_name = method;
                            break;
                        }
                        case OpCode::LOP_CALL: {
                            std::vector<ExprPtr> args;
                            for (int j = 1; j < ins.b; ++j)
                                args.push_back(get_reg(ins.a + j));
                            auto call = std::make_shared<CallExpr>(get_reg(ins.a), args);
                            if (i > 0 && p.instructions[i - 1].op == OpCode::LOP_NAMECALL) {
                                call->is_method = true;
                                auto& prev = p.instructions[i - 1];
                                call->method_name = p.constants[prev.aux];
                                call->method_name = call->method_name.substr(1, call->method_name.size() - 2);
                            }
                            if (ins.c > 1) {
                                block->statements.push_back(set_reg(ins.a, call));
                            }
                            else {
                                // statement form (call ignored results)
                                block->statements.push_back(std::make_shared<AssignStmt>(
                                    std::make_shared<VarExpr>("--call"), call));
                            }
                            break;
                        }
                        case OpCode::LOP_RETURN: {
                            std::vector<ExprPtr> ret_vals;
                            for (int j = 0; j < ins.b - 1; ++j)
                                ret_vals.push_back(get_reg(ins.a + j));
                            block->statements.push_back(std::make_shared<ReturnStmt>(ret_vals));
                            break;
                        }
                        case OpCode::LOP_NEWCLOSURE:
                        case OpCode::LOP_DUPCLOSURE: {
                            int proto_id = ins.d;
                            auto closure = std::make_shared<ClosureExpr>(proto_id);
                            std::string lifted = lift_proto(proto_id, indent + 1);
                            closure->cached_code = std::make_shared<std::string>(lifted);
                            block->statements.push_back(set_reg(ins.a, closure));
                            break;
                        }
                        default:
                          // comment
                            std::stringstream ss;
                            ss << "-- unknown op: " << (int)ins.op;
                            block->statements.push_back(std::make_shared<AssignStmt>(
                                std::make_shared<VarExpr>(ss.str()), std::make_shared<LiteralExpr>("?")));
                            break;
                        }
                    }

                    if (bb.is_cond) {
                        auto if_stmt = std::make_shared<IfStmt>(extract_cond(bb.end_pc, p.instructions[bb.end_pc]));
                        if_stmt->then_block = build_block(bb.true_target, bb.false_target);
                        if (bb.false_target != -1 && bb.false_target != limit_pc)
                            if_stmt->else_block = build_block(bb.false_target, limit_pc);
                        // 
                        if (if_stmt->else_block && if_stmt->else_block->statements.size() == 1 &&
                            if_stmt->else_block->statements[0]->type == Statement::Type::If) {
                            auto nested = std::static_pointer_cast<IfStmt>(if_stmt->else_block->statements[0]);
                            if_stmt->elseif_chain.push_back(nested);
                            if_stmt->else_block = nested->else_block;
                        }
                        block->statements.push_back(if_stmt);
                        return block;
                    }
                    else if (bb.is_jump) {
                        cur = bb.true_target;
                        continue;
                    }
                    else if (bb.is_ret) {
                        return block;
                    }
                    else {
                        cur = bb.true_target;
                        continue;
                    }
                next_block:;
                }
                return block;
                };

            std::stringstream ss;
            std::string pad(indent * 2, ' ');
            ss << pad << "function(";
            for (int i = 0; i < p.num_params; ++i)
                ss << (i == 0 ? "" : ", ") << "arg" << i;
            if (p.is_vararg) ss << (p.num_params ? ", " : "") << "...";
            ss << ")\n";
            ss << build_block(0, -1)->to_string(indent + 1);
            ss << pad << "end";
            return ss.str();
        }

        struct hash_pair {
            template <class T1, class T2>
            std::size_t operator()(const std::pair<T1, T2>& p) const {
                auto h1 = std::hash<T1>{}(p.first);
                auto h2 = std::hash<T2>{}(p.second);
                return h1 ^ (h2 << 1);
            }
        };

        static bool is_cond_jump(OpCode op) {
            return op == OpCode::LOP_JUMPIF || op == OpCode::LOP_JUMPIFNOT ||
                (static_cast<uint8_t>(op) >= static_cast<uint8_t>(OpCode::LOP_JUMPIFEQ) &&
                    static_cast<uint8_t>(op) <= static_cast<uint8_t>(OpCode::LOP_JUMPIFNOTLT)) ||
                op == OpCode::LOP_JUMPIFEQK || op == OpCode::LOP_JUMPIFNOTEQK;
        }
    };

}
