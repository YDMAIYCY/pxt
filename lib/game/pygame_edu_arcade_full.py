import pygame
import random
import sys
from collections import deque
from dataclasses import dataclass


# ==========================================================
# 配置区域
# ==========================================================
pygame.init()
pygame.font.init()

WIDTH, HEIGHT = 1440, 920
SCREEN = pygame.display.set_mode((WIDTH, HEIGHT))
pygame.display.set_caption("益智闯关乐园")
CLOCK = pygame.time.Clock()
FPS = 60

BG = (245, 248, 255)
PANEL = (255, 255, 255)
TEXT = (35, 45, 65)
SUB = (100, 110, 130)
BLUE = (72, 135, 255)
BLUE_D = (50, 105, 220)
GREEN = (74, 191, 118)
GREEN_D = (52, 150, 92)
ORANGE = (255, 167, 62)
RED = (230, 85, 85)
PURPLE = (150, 110, 255)
GRAY = (220, 226, 236)
DARK = (66, 78, 96)
YELLOW = (255, 224, 102)

FONT_XL = pygame.font.SysFont("microsoftyahei", 46, bold=True)
FONT_L = pygame.font.SysFont("microsoftyahei", 34, bold=True)
FONT_M = pygame.font.SysFont("microsoftyahei", 26)
FONT_MB = pygame.font.SysFont("microsoftyahei", 26, bold=True)
FONT_S = pygame.font.SysFont("microsoftyahei", 20)
FONT_TINY = pygame.font.SysFont("microsoftyahei", 16)

LEVEL_NAMES = [
    "第一关：找规律",
    "第二关：口算达人",
    "第三关：记忆卡片",
    "第四关：扫雷挑战",
    "第五关：数字华容道",
    "第六关：推箱子挑战",
    "第七关：成语寻踪",
    "第八关：贪吃蛇冲刺",
]
LEVEL_MAX_SCORE = [100] * len(LEVEL_NAMES)


# ==========================================================
# 通用工具
# ==========================================================
def draw_text(text, font, color, x, y, center=False):
    img = font.render(str(text), True, color)
    rect = img.get_rect()
    if center:
        rect.center = (x, y)
    else:
        rect.topleft = (x, y)
    SCREEN.blit(img, rect)
    return rect


def wrap_text(text, font, max_width):
    text = str(text)
    if not text:
        return [""]

    lines = []
    current = ""
    for ch in text:
        if ch == "\n":
            lines.append(current)
            current = ""
            continue
        test = current + ch
        if current and font.size(test)[0] > max_width:
            lines.append(current)
            current = ch
        else:
            current = test
    if current or not lines:
        lines.append(current)
    return lines


def draw_wrapped_text(text, font, color, rect, line_gap=8, center=False):
    lines = wrap_text(text, font, rect.width)
    total_height = len(lines) * font.get_height() + max(0, len(lines) - 1) * line_gap
    y = rect.top
    if center:
        y = rect.top + max(0, (rect.height - total_height) // 2)

    for line in lines:
        if center:
            draw_text(line, font, color, rect.centerx, y + font.get_height() // 2, center=True)
        else:
            draw_text(line, font, color, rect.left, y)
        y += font.get_height() + line_gap
    return y


def round_rect(surface, color, rect, radius=16, border=0, border_color=(0, 0, 0)):
    pygame.draw.rect(surface, color, rect, border_radius=radius)
    if border > 0:
        pygame.draw.rect(surface, border_color, rect, border, border_radius=radius)


class Button:
    def __init__(self, x, y, w, h, text, color=BLUE, hover=None, text_color=(255, 255, 255), font=FONT_MB):
        self.rect = pygame.Rect(x, y, w, h)
        self.text = text
        self.color = color
        self.hover = hover or color
        self.text_color = text_color
        self.font = font

    def draw(self, mouse_pos):
        c = self.hover if self.rect.collidepoint(mouse_pos) else self.color
        round_rect(SCREEN, c, self.rect, 16)
        draw_text(self.text, self.font, self.text_color, self.rect.centerx, self.rect.centery, center=True)

    def clicked(self, event):
        return event.type == pygame.MOUSEBUTTONDOWN and event.button == 1 and self.rect.collidepoint(event.pos)


def make_card_colors(n):
    base = [
        (255, 102, 102), (102, 178, 255), (102, 204, 153), (255, 179, 71),
        (186, 104, 200), (255, 140, 148), (129, 199, 132), (255, 214, 102),
    ]
    return base[:n]


def build_numeric_options(answer, minimum=0, maximum=None, preferred=None):
    options = [answer]
    for value in preferred or []:
        if value == answer:
            continue
        if value < minimum:
            continue
        if maximum is not None and value > maximum:
            continue
        if value not in options:
            options.append(value)

    deltas = [-18, -12, -9, -7, -5, -4, -3, 3, 4, 5, 7, 9, 12, 18]
    while len(options) < 4:
        delta = random.choice(deltas)
        candidate = answer + delta
        if candidate == answer or candidate in options:
            continue
        if candidate < minimum:
            continue
        if maximum is not None and candidate > maximum:
            continue
        options.append(candidate)

    random.shuffle(options)
    return options[:4]


def count_inversions(nums):
    arr = [x for x in nums if x != 0]
    inv = 0
    for i in range(len(arr)):
        for j in range(i + 1, len(arr)):
            if arr[i] > arr[j]:
                inv += 1
    return inv


def is_slide_solvable(nums, size):
    inv = count_inversions(nums)
    if size % 2 == 1:
        return inv % 2 == 0

    blank_row_from_bottom = size - (nums.index(0) // size)
    if blank_row_from_bottom % 2 == 0:
        return inv % 2 == 1
    return inv % 2 == 0


def shuffle_until_solvable(size):
    goal = list(range(1, size * size)) + [0]
    while True:
        candidate = goal[:]
        random.shuffle(candidate)
        misplaced = sum(1 for idx, value in enumerate(candidate) if value != 0 and value != goal[idx])
        if candidate != goal and misplaced >= size + 3 and is_slide_solvable(candidate, size):
            return candidate


# ==========================================================
# 数据结构
# ==========================================================
@dataclass
class LevelState:
    name: str
    status: str = "pending"   # pending / cleared / skipped
    score: int = 0
    best_msg: str = "未开始"


# ==========================================================
# 游戏1：找规律
# ==========================================================
class PatternGame:
    def __init__(self):
        self.reset()

    def reset(self):
        self.question_index = 0
        self.total_questions = 5
        self.correct = 0
        self.finished = False
        self.feedback = "这次不再出重复套路题，每题的规律都不一样。"
        bank = self.build_question_bank()
        random.shuffle(bank)
        self.questions = bank[:self.total_questions]
        self.load_current_question()

    def build_question_bank(self):
        bank = []

        start = random.randint(4, 10)
        step = random.choice([3, 4, 5, 6])
        seq = [start + step * i for i in range(5)]
        answer = start + step * 5
        bank.append({
            "prompt": f"观察等差规律：{seq[0]}，{seq[1]}，{seq[2]}，{seq[3]}，{seq[4]}，？",
            "answer": answer,
            "options": build_numeric_options(answer, minimum=0, preferred=[answer + step, answer - step, answer + 2 * step]),
        })

        start = random.randint(2, 4)
        mul = random.choice([2, 3])
        seq = [start * (mul ** i) for i in range(5)]
        answer = start * (mul ** 5)
        bank.append({
            "prompt": f"观察倍数规律：{seq[0]}，{seq[1]}，{seq[2]}，{seq[3]}，{seq[4]}，？",
            "answer": answer,
            "options": build_numeric_options(answer, minimum=1, preferred=[answer * mul, answer // mul, answer + mul * 3]),
        })

        start = random.randint(1, 4)
        diff = random.randint(2, 4)
        growth = random.randint(1, 2)
        seq = [start]
        current_diff = diff
        while len(seq) < 6:
            seq.append(seq[-1] + current_diff)
            current_diff += growth
        answer = seq[-1]
        bank.append({
            "prompt": f"差值在悄悄变大：{seq[0]}，{seq[1]}，{seq[2]}，{seq[3]}，{seq[4]}，？",
            "answer": answer,
            "options": build_numeric_options(answer, minimum=0, preferred=[answer + growth, answer - growth - 1, answer - current_diff]),
        })

        a = random.randint(1, 3)
        b = random.randint(2, 4)
        seq = [a, b]
        while len(seq) < 6:
            seq.append(seq[-1] + seq[-2])
        answer = seq[-1]
        bank.append({
            "prompt": f"后一个数等于前两个数之和：{seq[0]}，{seq[1]}，{seq[2]}，{seq[3]}，{seq[4]}，？",
            "answer": answer,
            "options": build_numeric_options(answer, minimum=0, preferred=[answer + seq[2], answer - seq[1], seq[-2] + seq[-3]]),
        })

        seq = [1, 4, 9, 16, 25]
        bank.append({
            "prompt": f"观察平方数规律：{seq[0]}，{seq[1]}，{seq[2]}，{seq[3]}，{seq[4]}，？",
            "answer": 36,
            "options": build_numeric_options(36, minimum=1, preferred=[30, 42, 49]),
        })

        seq = [1, 3, 6, 10, 15]
        bank.append({
            "prompt": f"每次多加 1 个单位：{seq[0]}，{seq[1]}，{seq[2]}，{seq[3]}，{seq[4]}，？",
            "answer": 21,
            "options": build_numeric_options(21, minimum=1, preferred=[18, 20, 28]),
        })

        odd_start = random.randint(2, 5)
        even_start = random.randint(8, 12)
        odd_step = random.choice([2, 3])
        even_step = random.choice([3, 4])
        seq = []
        odd_value = odd_start
        even_value = even_start
        for idx in range(6):
            if idx % 2 == 0:
                seq.append(odd_value)
                odd_value += odd_step
            else:
                seq.append(even_value)
                even_value += even_step
        answer = odd_value
        bank.append({
            "prompt": f"奇数位和偶数位各自成规律：{seq[0]}，{seq[1]}，{seq[2]}，{seq[3]}，{seq[4]}，{seq[5]}，？",
            "answer": answer,
            "options": build_numeric_options(answer, minimum=0, preferred=[answer + 1, seq[-1] + odd_step, answer - odd_step]),
        })

        bank.append({
            "prompt": "循环规律是哪个：春，夏，秋，冬，春，？",
            "answer": "夏",
            "options": ["夏", "秋", "冬", "春"],
        })

        bank.append({
            "prompt": "按方向顺时针变化：东，南，西，北，东，？",
            "answer": "南",
            "options": ["南", "西", "北", "东"],
        })

        bank.append({
            "prompt": "颜色循环规律：红，蓝，黄，绿，红，蓝，？",
            "answer": "黄",
            "options": ["黄", "绿", "红", "蓝"],
        })

        bank.append({
            "prompt": "一天中的时间顺序：早晨，中午，傍晚，夜晚，早晨，？",
            "answer": "中午",
            "options": ["中午", "傍晚", "夜晚", "清晨"],
        })

        bank.append({
            "prompt": "观察质数规律：2，3，5，7，11，？",
            "answer": 13,
            "options": build_numeric_options(13, minimum=1, preferred=[15, 17, 19]),
        })

        return bank

    def load_current_question(self):
        current = self.questions[self.question_index]
        self.prompt = current["prompt"]
        self.answer = current["answer"]
        self.options = current["options"][:]
        random.shuffle(self.options)
        self.option_rects = []

    def handle_event(self, event):
        if self.finished:
            return
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            for idx, rect in enumerate(self.option_rects):
                if rect.collidepoint(event.pos):
                    if self.options[idx] == self.answer:
                        self.correct += 1
                        self.feedback = "回答正确，这题的规律判断对了。"
                    else:
                        self.feedback = f"回答错误，正确答案是 {self.answer}。"
                    self.question_index += 1
                    if self.question_index >= self.total_questions:
                        self.finished = True
                    else:
                        self.load_current_question()
                    break

    def draw(self):
        panel = pygame.Rect(150, 118, WIDTH - 300, HEIGHT - 230)
        round_rect(SCREEN, PANEL, panel, 24)
        draw_text("找规律", FONT_L, TEXT, 190, 155)
        draw_text(f"题目进度：{self.question_index + (0 if self.finished else 1)}/{self.total_questions}", FONT_M, SUB, panel.right - 330, 162)

        prompt_text = self.prompt if not self.finished else f"完成啦，你一共答对了 {self.correct} 题。"
        draw_wrapped_text(prompt_text, FONT_L, DARK, pygame.Rect(200, 235, panel.width - 100, 110))
        draw_wrapped_text(self.feedback, FONT_M, ORANGE if "错误" in self.feedback else GREEN, pygame.Rect(200, 335, panel.width - 100, 60))

        self.option_rects = []
        if not self.finished:
            start_x = 240
            start_y = 430
            btn_w = 360
            btn_h = 88
            gap_x = 220
            gap_y = 36
            for row in range(2):
                for col in range(2):
                    idx = row * 2 + col
                    rect = pygame.Rect(start_x + col * (btn_w + gap_x), start_y + row * (btn_h + gap_y), btn_w, btn_h)
                    self.option_rects.append(rect)
                    round_rect(SCREEN, BLUE if idx % 2 == 0 else PURPLE, rect, 18)
                    draw_text(self.options[idx], FONT_L, (255, 255, 255), rect.centerx, rect.centery, center=True)
        else:
            score = self.get_score()
            draw_text(f"本关得分：{score}", FONT_L, GREEN, 200, 500)
            draw_wrapped_text("这一轮题目已经尽量避免重复，你可以继续下一关。", FONT_M, SUB, pygame.Rect(200, 565, panel.width - 120, 60))

    def is_finished(self):
        return self.finished

    def get_score(self):
        return self.correct * 20

    def get_message(self):
        return f"答对 {self.correct}/{self.total_questions} 题"


# ==========================================================
# 游戏2：口算达人
# ==========================================================
class MathGame:
    def __init__(self):
        self.reset()

    def reset(self):
        self.total_questions = 8
        self.index = 0
        self.correct = 0
        self.finished = False
        self.feedback = "这关改成了混合题型，同一轮不会反复刷同一种题。"
        bank = self.build_question_bank()
        random.shuffle(bank)
        self.questions = bank[:self.total_questions]
        self.load_current_question()

    def build_question_bank(self):
        bank = []

        a, b, c = random.randint(18, 35), random.randint(12, 24), random.randint(6, 14)
        answer = a + b - c
        bank.append({
            "prompt": f"直接计算：{a} + {b} - {c} = ？",
            "answer": answer,
            "options": build_numeric_options(answer, minimum=0, preferred=[answer + 3, answer - 4, a + c]),
        })

        a, b, c = random.randint(6, 9), random.randint(4, 8), random.randint(8, 18)
        answer = a * b - c
        bank.append({
            "prompt": f"先乘后减：{a} × {b} - {c} = ？",
            "answer": answer,
            "options": build_numeric_options(answer, minimum=0, preferred=[a * b, answer + b, answer - a]),
        })

        a, b, c = random.randint(8, 18), random.randint(6, 12), random.randint(2, 4)
        answer = (a + b) * c
        bank.append({
            "prompt": f"带括号计算：（{a} + {b}）× {c} = ？",
            "answer": answer,
            "options": build_numeric_options(answer, minimum=0, preferred=[a + b * c, answer - c, answer + a]),
        })

        a, b, c = random.randint(5, 9), random.randint(8, 14), random.randint(2, 5)
        answer = a * (b - c)
        bank.append({
            "prompt": f"再算括号里的差：{a} × （{b} - {c}）= ？",
            "answer": answer,
            "options": build_numeric_options(answer, minimum=0, preferred=[a * b - c, a * (b + c), answer - a]),
        })

        divisor = random.randint(3, 8)
        quotient = random.randint(6, 12)
        extra = random.randint(8, 18)
        answer = quotient + extra
        bank.append({
            "prompt": f"先除后加：{divisor * quotient} ÷ {divisor} + {extra} = ？",
            "answer": answer,
            "options": build_numeric_options(answer, minimum=0, preferred=[quotient * extra, quotient, answer + divisor]),
        })

        divisor = random.randint(2, 5)
        target = random.randint(8, 14)
        add_a = random.randint(10, 24)
        add_b = divisor * target - add_a
        answer = target
        bank.append({
            "prompt": f"带括号计算：（{add_a} + {add_b}）÷ {divisor} = ？",
            "answer": answer,
            "options": build_numeric_options(answer, minimum=1, preferred=[target + divisor, target - 2, add_a // divisor]),
        })

        answer = random.randint(12, 26)
        b = random.randint(8, 18)
        c = answer + b
        bank.append({
            "prompt": f"填空：□ + {b} = {c}，□ 应该填几？",
            "answer": answer,
            "options": build_numeric_options(answer, minimum=0, preferred=[c - 1, b, answer + 5]),
        })

        answer = random.randint(4, 12)
        factor = random.randint(5, 9)
        result = answer * factor
        bank.append({
            "prompt": f"填空：□ × {factor} = {result}，□ 应该填几？",
            "answer": answer,
            "options": build_numeric_options(answer, minimum=1, preferred=[factor, answer + 2, result - factor]),
        })

        length = random.randint(6, 12)
        width = random.randint(4, 9)
        answer = 2 * (length + width)
        bank.append({
            "prompt": f"一个长方形长 {length} 米、宽 {width} 米，它的周长是多少米？",
            "answer": answer,
            "options": build_numeric_options(answer, minimum=0, preferred=[length * width, length + width, answer + 4]),
        })

        per_box = random.randint(8, 15)
        boxes = random.randint(3, 5)
        bonus = random.randint(3, 8)
        answer = per_box * boxes + bonus
        bank.append({
            "prompt": f"一盒彩笔有 {per_box} 支，买 {boxes} 盒后又奖励 {bonus} 支，一共有多少支？",
            "answer": answer,
            "options": build_numeric_options(answer, minimum=0, preferred=[per_box * boxes, per_box + boxes + bonus, answer - bonus]),
        })

        total = random.randint(28, 48)
        give = random.randint(7, 15)
        buy = random.randint(4, 10)
        answer = total - give + buy
        bank.append({
            "prompt": f"小明原来有 {total} 本书，借给同学 {give} 本，又新买了 {buy} 本，现在有多少本？",
            "answer": answer,
            "options": build_numeric_options(answer, minimum=0, preferred=[total - give, total + buy, answer - 2]),
        })

        each = random.randint(5, 9)
        students = random.randint(4, 7)
        answer = each
        total = each * students
        bank.append({
            "prompt": f"把 {total} 个苹果平均分给 {students} 个同学，每人能分到多少个？",
            "answer": answer,
            "options": build_numeric_options(answer, minimum=1, preferred=[students, total - students, answer + 3]),
        })

        return bank

    def load_current_question(self):
        current = self.questions[self.index]
        self.prompt = current["prompt"]
        self.answer = current["answer"]
        self.options = current["options"][:]
        random.shuffle(self.options)
        self.option_rects = []

    def handle_event(self, event):
        if self.finished:
            return
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            for idx, rect in enumerate(self.option_rects):
                if rect.collidepoint(event.pos):
                    if self.options[idx] == self.answer:
                        self.correct += 1
                        self.feedback = "答对了，这题算得很稳。"
                    else:
                        self.feedback = f"答错了，正确答案是 {self.answer}。"
                    self.index += 1
                    if self.index >= self.total_questions:
                        self.finished = True
                    else:
                        self.load_current_question()
                    break

    def draw(self):
        panel = pygame.Rect(150, 118, WIDTH - 300, HEIGHT - 230)
        round_rect(SCREEN, PANEL, panel, 24)
        draw_text("口算达人", FONT_L, TEXT, 190, 155)
        draw_text(f"题目进度：{self.index + (0 if self.finished else 1)}/{self.total_questions}", FONT_M, SUB, panel.right - 330, 162)

        if not self.finished:
            draw_wrapped_text(self.prompt, FONT_L, DARK, pygame.Rect(220, 235, panel.width - 140, 120), line_gap=10, center=True)
            draw_wrapped_text(self.feedback, FONT_M, ORANGE if "错" in self.feedback else GREEN, pygame.Rect(220, 355, panel.width - 140, 50), center=True)

            start_x = 240
            start_y = 460
            btn_w = 360
            btn_h = 88
            gap_x = 220
            gap_y = 36
            self.option_rects = []
            for row in range(2):
                for col in range(2):
                    idx = row * 2 + col
                    rect = pygame.Rect(start_x + col * (btn_w + gap_x), start_y + row * (btn_h + gap_y), btn_w, btn_h)
                    self.option_rects.append(rect)
                    round_rect(SCREEN, GREEN if idx % 2 == 0 else BLUE, rect, 18)
                    draw_text(self.options[idx], FONT_L, (255, 255, 255), rect.centerx, rect.centery, center=True)
        else:
            score = self.get_score()
            draw_text(f"完成！你答对了 {self.correct}/{self.total_questions} 题。", FONT_L, DARK, 200, 320)
            draw_text(f"本关得分：{score}", FONT_L, GREEN, 200, 410)
            draw_wrapped_text("这次题型包含了混合运算、填空题和应用题，不会一直重复同一种计算。", FONT_M, SUB, pygame.Rect(200, 500, panel.width - 120, 70))

    def is_finished(self):
        return self.finished

    def get_score(self):
        return int(self.correct / self.total_questions * 100)

    def get_message(self):
        return f"答对 {self.correct}/{self.total_questions} 题"


# ==========================================================
# 游戏3：记忆翻牌
# ==========================================================
class MemoryGame:
    def __init__(self):
        self.reset()

    def reset(self):
        values = list(range(1, 9)) * 2
        random.shuffle(values)
        self.cards = values
        self.revealed = [False] * 16
        self.matched = [False] * 16
        self.first = None
        self.second = None
        self.wait_timer = 0
        self.moves = 0
        self.finished = False
        self.grid_rects = []
        self.colors = make_card_colors(8)

    def handle_event(self, event):
        if self.finished or self.wait_timer > 0:
            return
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            for idx, rect in enumerate(self.grid_rects):
                if rect.collidepoint(event.pos) and not self.revealed[idx] and not self.matched[idx]:
                    self.revealed[idx] = True
                    if self.first is None:
                        self.first = idx
                    elif self.second is None and idx != self.first:
                        self.second = idx
                        self.moves += 1
                        if self.cards[self.first] == self.cards[self.second]:
                            self.matched[self.first] = True
                            self.matched[self.second] = True
                            self.first = None
                            self.second = None
                            if all(self.matched):
                                self.finished = True
                        else:
                            self.wait_timer = 40
                    break

    def update(self):
        if self.wait_timer > 0:
            self.wait_timer -= 1
            if self.wait_timer == 0 and self.first is not None and self.second is not None:
                self.revealed[self.first] = False
                self.revealed[self.second] = False
                self.first = None
                self.second = None

    def draw(self):
        panel = pygame.Rect(150, 118, WIDTH - 300, HEIGHT - 230)
        round_rect(SCREEN, PANEL, panel, 24)
        draw_text("记忆卡片：翻牌配对", FONT_L, TEXT, 190, 155)
        draw_text(f"已尝试：{self.moves} 次", FONT_M, SUB, panel.right - 260, 162)
        draw_wrapped_text("规则：一次翻开两张卡片，记住位置并找到所有相同数字。", FONT_M, SUB, pygame.Rect(190, 205, 620, 50))

        size = 138
        gap = 18
        grid_w = size * 4 + gap * 3
        start_x = WIDTH // 2 - grid_w // 2
        start_y = 290
        self.grid_rects = []

        for row in range(4):
            for col in range(4):
                idx = row * 4 + col
                rect = pygame.Rect(start_x + col * (size + gap), start_y + row * (size + gap), size, size)
                self.grid_rects.append(rect)
                if self.revealed[idx] or self.matched[idx]:
                    color = self.colors[(self.cards[idx] - 1) % len(self.colors)]
                    round_rect(SCREEN, color, rect, 18)
                    draw_text(self.cards[idx], FONT_XL, (255, 255, 255), rect.centerx, rect.centery, center=True)
                else:
                    round_rect(SCREEN, BLUE_D, rect, 18)
                    draw_text("?", FONT_XL, (255, 255, 255), rect.centerx, rect.centery, center=True)

        if self.finished:
            draw_text("全部配对完成！", FONT_L, GREEN, WIDTH // 2, 250, center=True)
            draw_text(f"本关得分：{self.get_score()}", FONT_L, ORANGE, WIDTH // 2, panel.bottom - 40, center=True)

    def is_finished(self):
        return self.finished

    def get_score(self):
        score = 100 - max(0, self.moves - 8) * 8
        return max(40, score)

    def get_message(self):
        return f"共用了 {self.moves} 步"


# ==========================================================
# 游戏4：双阶段扫雷
# ==========================================================
class MinesweeperGame:
    NUMBER_COLORS = {
        1: BLUE_D,
        2: GREEN_D,
        3: RED,
        4: PURPLE,
        5: ORANGE,
        6: (37, 145, 160),
        7: DARK,
        8: SUB,
    }

    def __init__(self):
        self.reset()

    def reset(self):
        self.stages = [
            {"name": "训练场", "rows": 8, "cols": 8, "mines": 3, "cell": 50},
            {"name": "进阶场", "rows": 11, "cols": 11, "mines": 5, "cell": 38},
        ]
        self.stage_index = 0
        self.total_restarts = 0
        self.finished = False
        self.completed_stages = []
        self.feedback = "第四关是双阶段扫雷：先完成更简单的训练场，再进入稍难一点的进阶场。"
        self.load_stage(reset_counter=True)

    def load_stage(self, reset_counter):
        config = self.stages[self.stage_index]
        self.stage_name = config["name"]
        self.rows = config["rows"]
        self.cols = config["cols"]
        self.mine_total = config["mines"]
        self.cell = config["cell"]
        if reset_counter:
            self.stage_restarts = 0
        self.build_board()

    def build_board(self):
        all_cells = [(r, c) for r in range(self.rows) for c in range(self.cols)]
        self.mine_positions = set(random.sample(all_cells, self.mine_total))
        self.adjacent_counts = {}
        for row in range(self.rows):
            for col in range(self.cols):
                cell = (row, col)
                if cell in self.mine_positions:
                    continue
                self.adjacent_counts[cell] = sum(1 for nxt in self.neighbors(row, col) if nxt in self.mine_positions)

        self.revealed = set()
        self.flagged = set()
        self.grid_rects = []
        board_width = self.cols * self.cell
        board_height = self.rows * self.cell
        self.offset_x = 720 + max(0, (470 - board_width) // 2)
        self.offset_y = 215 + max(0, (500 - board_height) // 2)

    def neighbors(self, row, col):
        for dr in [-1, 0, 1]:
            for dc in [-1, 0, 1]:
                if dr == 0 and dc == 0:
                    continue
                nr, nc = row + dr, col + dc
                if 0 <= nr < self.rows and 0 <= nc < self.cols:
                    yield nr, nc

    def remaining_hidden_safe(self):
        safe_total = self.rows * self.cols - self.mine_total
        return safe_total - len(self.revealed)

    def ensure_safe_first_click(self, row, col):
        if self.revealed or self.flagged or (row, col) not in self.mine_positions:
            return
        while (row, col) in self.mine_positions:
            self.build_board()

    def reveal_cell(self, row, col):
        cell = (row, col)
        if cell in self.flagged or cell in self.revealed:
            return

        self.ensure_safe_first_click(row, col)
        if cell in self.mine_positions:
            self.restart_stage("踩到雷了，本阶段已经重新开始。")
            return

        queue = deque([cell])
        seen = {cell}
        while queue:
            current = queue.popleft()
            if current in self.revealed or current in self.flagged or current in self.mine_positions:
                continue

            self.revealed.add(current)
            if self.adjacent_counts[current] == 0:
                for nxt in self.neighbors(*current):
                    if nxt not in seen and nxt not in self.flagged:
                        seen.add(nxt)
                        queue.append(nxt)

        count = self.adjacent_counts[cell]
        if count == 0:
            self.feedback = "这一片是安全区，可以继续顺着数字排查。"
        else:
            self.feedback = f"这个格子周围有 {count} 个雷。"

    def toggle_flag(self, row, col):
        cell = (row, col)
        if cell in self.revealed:
            return

        if cell in self.flagged:
            self.flagged.remove(cell)
            self.feedback = f"已取消标旗，目前标出 {len(self.flagged)}/{self.mine_total} 个位置。"
            return

        if len(self.flagged) >= self.mine_total:
            self.feedback = f"这一阶段共有 {self.mine_total} 个雷，旗子数量已经用满了。"
            return

        self.flagged.add(cell)
        self.feedback = f"已标旗 {len(self.flagged)}/{self.mine_total}。继续核对所有数字关系。"
        self.check_stage_clear()

    def check_stage_clear(self):
        if len(self.flagged) == self.mine_total and self.flagged == self.mine_positions:
            completed_name = self.stage_name
            self.completed_stages.append(completed_name)
            if self.stage_index < len(self.stages) - 1:
                self.stage_index += 1
                self.load_stage(reset_counter=True)
                self.feedback = f"{completed_name}已完成，现在进入{self.stage_name}。第二张图会更大、雷也更多。"
            else:
                self.finished = True
                self.feedback = f"两张扫雷图全部完成，你已经准确标出了全部 {sum(stage['mines'] for stage in self.stages)} 个雷。"
        elif len(self.flagged) == self.mine_total:
            self.feedback = "旗子数量已经用满，但还没有把所有雷都找对。"

    def restart_stage(self, message):
        self.total_restarts += 1
        self.stage_restarts += 1
        self.build_board()
        self.feedback = message

    def handle_event(self, event):
        if self.finished:
            return

        if event.type == pygame.KEYDOWN and event.key == pygame.K_r:
            self.restart_stage("你手动重开了这一张扫雷图。")
            return

        if event.type == pygame.MOUSEBUTTONDOWN:
            if not self.grid_rects:
                return
            for row in range(self.rows):
                for col in range(self.cols):
                    rect = self.grid_rects[row][col]
                    if rect.collidepoint(event.pos):
                        if event.button == 1:
                            self.reveal_cell(row, col)
                        elif event.button == 3:
                            self.toggle_flag(row, col)
                        return

    def draw_board(self):
        board_rect = pygame.Rect(
            self.offset_x - 16,
            self.offset_y - 16,
            self.cols * self.cell + 32,
            self.rows * self.cell + 32,
        )
        round_rect(SCREEN, (242, 246, 255), board_rect, 24)
        self.grid_rects = []

        for row in range(self.rows):
            rect_row = []
            for col in range(self.cols):
                rect = pygame.Rect(
                    self.offset_x + col * self.cell,
                    self.offset_y + row * self.cell,
                    self.cell - 2,
                    self.cell - 2,
                )
                rect_row.append(rect)
                cell = (row, col)

                if cell in self.revealed:
                    round_rect(SCREEN, (250, 252, 255), rect, 10, border=1, border_color=GRAY)
                    number = self.adjacent_counts[cell]
                    if number > 0:
                        draw_text(str(number), FONT_M, self.NUMBER_COLORS.get(number, TEXT), rect.centerx, rect.centery, center=True)
                elif cell in self.flagged:
                    round_rect(SCREEN, ORANGE, rect, 10, border=1, border_color=(224, 140, 42))
                    draw_text("旗", FONT_S, (255, 255, 255), rect.centerx, rect.centery, center=True)
                else:
                    round_rect(SCREEN, BLUE, rect, 10, border=1, border_color=BLUE_D)
                    pygame.draw.rect(SCREEN, (123, 171, 255), pygame.Rect(rect.x + 4, rect.y + 4, rect.width - 8, 8), border_radius=4)
            self.grid_rects.append(rect_row)

    def draw(self):
        panel = pygame.Rect(150, 118, WIDTH - 300, HEIGHT - 230)
        round_rect(SCREEN, PANEL, panel, 24)
        draw_text("双阶段扫雷", FONT_L, TEXT, 190, 155)
        draw_text(f"当前阶段：{self.stage_index + 1}/{len(self.stages)}（{self.stage_name}）", FONT_M, SUB, 190, 215)
        draw_text(f"已标旗：{len(self.flagged)}/{self.mine_total}", FONT_M, SUB, 190, 255)
        draw_text(f"本阶段重开：{self.stage_restarts}", FONT_M, SUB, 190, 295)
        draw_text(f"总重开：{self.total_restarts}", FONT_M, SUB, 190, 335)

        rule_rect = pygame.Rect(190, 385, 420, 170)
        round_rect(SCREEN, (242, 246, 255), rule_rect, 20)
        draw_wrapped_text(
            "规则：左键翻开格子，右键标旗。第一张图更基础，第二张图只比第一张大一点、雷多一点。你不需要翻开所有安全格，只要把全部雷准确标出来就算通关；如果点到雷，当前阶段会立即重开。按 R 可以手动重开。",
            FONT_S,
            DARK,
            rule_rect.inflate(-24, -18),
            line_gap=8,
        )
        draw_wrapped_text(self.feedback, FONT_S, GREEN if self.finished else ORANGE, pygame.Rect(190, 585, 420, 130), line_gap=8)
        draw_text(f"剩余未翻安全格：{self.remaining_hidden_safe()}", FONT_S, SUB, 190, 732)
        draw_text("提示：先翻开大面积空白，再根据数字关系慢慢缩小范围。", FONT_S, SUB, 190, 760)

        self.draw_board()

        if self.finished:
            draw_text("两张扫雷图全部完成！", FONT_L, GREEN, 955, 742, center=True)

    def is_finished(self):
        return self.finished

    def get_score(self):
        return max(55, 100 - self.total_restarts * 8)

    def get_message(self):
        return f"完成 2 张扫雷图，共重开 {self.total_restarts} 次，最终准确标出全部 {sum(stage['mines'] for stage in self.stages)} 个雷"


# ==========================================================
# 游戏5：数字华容道
# ==========================================================
class SlidePuzzleGame:
    def __init__(self):
        self.reset()

    def reset(self):
        self.stage_sizes = [3, 4]
        self.stage_index = 0
        self.completed_stages = []
        self.total_moves = 0
        self.finished = False
        self.feedback = "先完成 3×3，再自动进入 4×4。"
        self.setup_stage()

    def setup_stage(self):
        self.size = self.stage_sizes[self.stage_index]
        self.goal = list(range(1, self.size * self.size)) + [0]
        self.tiles = shuffle_until_solvable(self.size)
        self.stage_moves = 0
        self.rects = []
        self.gap = 10
        self.tile_size = 122 if self.size == 3 else 90
        grid_width = self.size * self.tile_size + (self.size - 1) * self.gap
        self.offset_x = WIDTH // 2 - grid_width // 2
        self.offset_y = 280 if self.size == 3 else 240

    def idx_to_rc(self, idx):
        return idx // self.size, idx % self.size

    def neighbors(self, a, b):
        ra, ca = self.idx_to_rc(a)
        rb, cb = self.idx_to_rc(b)
        return abs(ra - rb) + abs(ca - cb) == 1

    def complete_current_stage(self):
        self.completed_stages.append(self.size)
        if self.stage_index < len(self.stage_sizes) - 1:
            finished_size = self.size
            self.stage_index += 1
            self.setup_stage()
            self.feedback = f"{finished_size}×{finished_size} 已完成，现在进入 4×4 阶段。"
        else:
            self.finished = True
            self.feedback = "3×3 和 4×4 都完成了，华容道全部通关。"

    def handle_event(self, event):
        if self.finished:
            return
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            for idx, rect in enumerate(self.rects):
                if rect.collidepoint(event.pos) and self.tiles[idx] != 0:
                    zero = self.tiles.index(0)
                    if self.neighbors(idx, zero):
                        self.tiles[zero], self.tiles[idx] = self.tiles[idx], self.tiles[zero]
                        self.stage_moves += 1
                        self.total_moves += 1
                        if self.tiles == self.goal:
                            self.complete_current_stage()
                    break

    def draw_stage_badges(self, panel):
        badge_y = 215
        for idx, size in enumerate(self.stage_sizes):
            rect = pygame.Rect(panel.right - 250 + idx * 110, badge_y, 90, 36)
            if size in self.completed_stages:
                color = GREEN
            elif idx == self.stage_index and not self.finished:
                color = BLUE
            else:
                color = GRAY
            round_rect(SCREEN, color, rect, 14)
            draw_text(f"{size}×{size}", FONT_S, (255, 255, 255) if color != GRAY else TEXT, rect.centerx, rect.centery, center=True)

    def draw(self):
        panel = pygame.Rect(150, 118, WIDTH - 300, HEIGHT - 230)
        round_rect(SCREEN, PANEL, panel, 24)
        draw_text("数字华容道", FONT_L, TEXT, 190, 155)
        draw_text(f"当前阶段：{self.size}×{self.size}", FONT_M, SUB, 190, 215)
        draw_text(f"本阶段移动：{self.stage_moves}", FONT_M, SUB, 190, 255)
        draw_text(f"总移动次数：{self.total_moves}", FONT_M, SUB, 190, 295)
        draw_wrapped_text("规则：点击与空白格相邻的数字块进行移动。3×3 完成后会自动解锁 4×4。", FONT_S, DARK, pygame.Rect(190, 340, 420, 70), line_gap=8)
        draw_wrapped_text(self.feedback, FONT_S, GREEN if self.finished else ORANGE, pygame.Rect(190, 430, 420, 80), line_gap=8)
        self.draw_stage_badges(panel)

        self.rects = []
        for idx, value in enumerate(self.tiles):
            row, col = self.idx_to_rc(idx)
            rect = pygame.Rect(
                self.offset_x + col * (self.tile_size + self.gap),
                self.offset_y + row * (self.tile_size + self.gap),
                self.tile_size,
                self.tile_size,
            )
            self.rects.append(rect)
            if value == 0:
                round_rect(SCREEN, GRAY, rect, 18)
            else:
                round_rect(SCREEN, ORANGE if value % 2 else PURPLE, rect, 18)
                draw_text(value, FONT_XL if self.size == 3 else FONT_L, (255, 255, 255), rect.centerx, rect.centery, center=True)

        if self.finished:
            draw_text("全部拼好了！", FONT_L, GREEN, WIDTH // 2, panel.bottom - 38, center=True)

    def is_finished(self):
        return self.finished

    def get_score(self):
        base = 100 - max(0, self.total_moves - 140) // 2
        return max(45, base)

    def get_message(self):
        return f"完成 3×3 和 4×4，共移动 {self.total_moves} 次"


# ==========================================================
# 游戏6：推箱子挑战
# ==========================================================
class SokobanGame:
    def __init__(self):
        self.reset()

    def reset(self):
        self.level_maps = [
            [
                "###########",
                "#   . .   #",
                "#   $ $   #",
                "# ### ### #",
                "#    @    #",
                "# ### ### #",
                "#   $ .   #",
                "#         #",
                "###########",
            ],
            [
                "#############",
                "#   .   .   #",
                "#   $ # $   #",
                "# ##     ## #",
                "# .   @   . #",
                "# ##  $  ## #",
                "#    #$#    #",
                "#           #",
                "#############",
            ],
        ]
        self.stage_index = 0
        self.finished = False
        self.completed_stages = []
        self.total_steps = 0
        self.total_pushes = 0
        self.restarts = 0
        self.feedback = "第六关改成了双阶段推箱子，难度比交换拼图高很多。"
        self.load_stage(self.stage_index)

    def load_stage(self, stage_index):
        self.stage_index = stage_index
        self.history = []
        self.stage_steps = 0
        self.stage_pushes = 0
        self.parse_map(self.level_maps[self.stage_index])

    def parse_map(self, lines):
        self.map_rows = len(lines)
        self.map_cols = max(len(line) for line in lines)
        self.walls = set()
        self.goals = set()
        self.boxes = set()
        self.player = (0, 0)

        for r, line in enumerate(lines):
            for c, ch in enumerate(line):
                pos = (r, c)
                if ch == "#":
                    self.walls.add(pos)
                elif ch == ".":
                    self.goals.add(pos)
                elif ch == "$":
                    self.boxes.add(pos)
                elif ch == "@":
                    self.player = pos
                elif ch == "*":
                    self.goals.add(pos)
                    self.boxes.add(pos)
                elif ch == "+":
                    self.goals.add(pos)
                    self.player = pos

        self.cell = min(62, max(46, 620 // max(self.map_rows, self.map_cols)))
        board_width = self.map_cols * self.cell
        self.offset_x = WIDTH - 180 - board_width
        self.offset_y = 260

    def stage_goal_count(self):
        return len(self.goals)

    def boxes_on_goal(self):
        return len(self.boxes & self.goals)

    def save_history(self):
        snapshot = (self.player, tuple(sorted(self.boxes)), self.stage_steps, self.stage_pushes, self.total_steps, self.total_pushes)
        self.history.append(snapshot)
        if len(self.history) > 120:
            self.history.pop(0)

    def undo(self):
        if not self.history:
            self.feedback = "当前还没有可以撤销的移动。"
            return
        player, boxes, stage_steps, stage_pushes, total_steps, total_pushes = self.history.pop()
        self.player = player
        self.boxes = set(boxes)
        self.stage_steps = stage_steps
        self.stage_pushes = stage_pushes
        self.total_steps = total_steps
        self.total_pushes = total_pushes
        self.feedback = "已撤销上一步。"

    def restart_stage(self):
        self.restarts += 1
        self.feedback = "本阶段已重新开始。"
        self.load_stage(self.stage_index)

    def complete_stage(self):
        self.completed_stages.append(self.stage_index + 1)
        if self.stage_index < len(self.level_maps) - 1:
            finished_stage = self.stage_index + 1
            self.load_stage(self.stage_index + 1)
            self.feedback = f"第 {finished_stage} 张地图完成，进入下一张更难的推箱子地图。"
        else:
            self.finished = True
            self.feedback = "两张推箱子地图都完成了，这一关已经全部通过。"

    def attempt_move(self, dr, dc):
        next_pos = (self.player[0] + dr, self.player[1] + dc)
        if next_pos in self.walls:
            return

        if next_pos in self.boxes:
            box_target = (next_pos[0] + dr, next_pos[1] + dc)
            if box_target in self.walls or box_target in self.boxes:
                return
            self.save_history()
            self.boxes.remove(next_pos)
            self.boxes.add(box_target)
            self.player = next_pos
            self.stage_pushes += 1
            self.total_pushes += 1
            self.stage_steps += 1
            self.total_steps += 1
            self.feedback = "成功推动了一个箱子。"
        else:
            self.save_history()
            self.player = next_pos
            self.stage_steps += 1
            self.total_steps += 1

        if self.boxes_on_goal() == self.stage_goal_count():
            self.complete_stage()

    def handle_event(self, event):
        if self.finished:
            return
        if event.type != pygame.KEYDOWN:
            return

        if event.key == pygame.K_r:
            self.restart_stage()
            return
        if event.key == pygame.K_u:
            self.undo()
            return

        dr, dc = 0, 0
        if event.key == pygame.K_UP:
            dr = -1
        elif event.key == pygame.K_DOWN:
            dr = 1
        elif event.key == pygame.K_LEFT:
            dc = -1
        elif event.key == pygame.K_RIGHT:
            dc = 1

        if dr != 0 or dc != 0:
            self.attempt_move(dr, dc)

    def draw_stage_badges(self, panel):
        badge_y = 215
        for idx in range(len(self.level_maps)):
            rect = pygame.Rect(panel.right - 260 + idx * 118, badge_y, 98, 36)
            if idx + 1 in self.completed_stages:
                color = GREEN
            elif idx == self.stage_index and not self.finished:
                color = BLUE
            else:
                color = GRAY
            round_rect(SCREEN, color, rect, 14)
            draw_text(f"地图 {idx + 1}", FONT_S, (255, 255, 255) if color != GRAY else TEXT, rect.centerx, rect.centery, center=True)

    def draw(self):
        panel = pygame.Rect(150, 118, WIDTH - 300, HEIGHT - 230)
        round_rect(SCREEN, PANEL, panel, 24)
        draw_text("推箱子挑战", FONT_L, TEXT, 190, 155)
        draw_text(f"当前地图：{self.stage_index + 1}/{len(self.level_maps)}", FONT_M, SUB, 190, 215)
        draw_text(f"本图步数：{self.stage_steps}", FONT_M, SUB, 190, 255)
        draw_text(f"推箱次数：{self.stage_pushes}", FONT_M, SUB, 190, 295)
        draw_text(f"目标完成：{self.boxes_on_goal()}/{self.stage_goal_count()}", FONT_M, SUB, 190, 335)
        draw_text(f"总重开次数：{self.restarts}", FONT_M, SUB, 190, 375)
        draw_wrapped_text("规则：方向键移动小人，遇到箱子时只能往前推，不能拉。所有箱子都推到目标点才算通过。按 U 可撤销一步，按 R 可重开当前地图。", FONT_S, DARK, pygame.Rect(190, 430, 410, 100), line_gap=8)
        draw_wrapped_text(self.feedback, FONT_S, GREEN if self.finished else ORANGE, pygame.Rect(190, 560, 410, 110), line_gap=8)
        self.draw_stage_badges(panel)

        for r in range(self.map_rows):
            for c in range(self.map_cols):
                rect = pygame.Rect(self.offset_x + c * self.cell, self.offset_y + r * self.cell, self.cell - 2, self.cell - 2)
                pos = (r, c)
                if pos in self.walls:
                    pygame.draw.rect(SCREEN, DARK, rect, border_radius=10)
                else:
                    pygame.draw.rect(SCREEN, (245, 247, 252), rect, border_radius=10)
                    if pos in self.goals:
                        pygame.draw.circle(SCREEN, YELLOW, rect.center, self.cell // 4)
                        draw_text("◎", FONT_TINY, TEXT, rect.centerx, rect.centery, center=True)

        for r, c in self.boxes:
            rect = pygame.Rect(self.offset_x + c * self.cell + 5, self.offset_y + r * self.cell + 5, self.cell - 12, self.cell - 12)
            on_goal = (r, c) in self.goals
            round_rect(SCREEN, GREEN if on_goal else ORANGE, rect, 12)
            draw_text("箱", FONT_S, (255, 255, 255), rect.centerx, rect.centery, center=True)

        player_rect = pygame.Rect(
            self.offset_x + self.player[1] * self.cell + 8,
            self.offset_y + self.player[0] * self.cell + 8,
            self.cell - 18,
            self.cell - 18,
        )
        pygame.draw.ellipse(SCREEN, RED, player_rect)

        if self.finished:
            draw_text("推箱子全部完成！", FONT_L, GREEN, WIDTH // 2, panel.bottom - 40, center=True)

    def is_finished(self):
        return self.finished

    def get_score(self):
        base = 100 - max(0, self.total_steps - 90) // 2 - self.total_pushes * 2 - self.restarts * 5
        return max(40, base)

    def get_message(self):
        return f"完成 {len(self.level_maps)} 张推箱子地图，共走 {self.total_steps} 步，推箱 {self.total_pushes} 次"


# ==========================================================
# 游戏7：成语寻踪挑战
# ==========================================================
class TypingGame:
    def __init__(self):
        self.reset()

    def reset(self):
        self.puzzle_bank = [
            {
                "clue": "形容说话做事坚决果断，毫不犹豫",
                "answer": "斩钉截铁",
                "decoys": list("剪叮接决刀锋快烈雷明山河"),
            },
            {
                "clue": "比喻忍辱负重，刻苦自励，等待时机",
                "answer": "卧薪尝胆",
                "decoys": list("坐柴品苦志勇寒热兵马风云"),
            },
            {
                "clue": "形容条理十分分明，整齐不乱",
                "answer": "井井有条",
                "decoys": list("木木成章清楚顺序分层丝路"),
            },
            {
                "clue": "比喻事情真相完全显露出来",
                "answer": "水落石出",
                "decoys": list("山高云起波沉火现真假迷踪"),
            },
            {
                "clue": "比喻做事之前心里已经有完整打算",
                "answer": "胸有成竹",
                "decoys": list("心怀妙策文墨画梅松兰风骨"),
            },
        ]
        self.puzzles = self.puzzle_bank[:]
        random.shuffle(self.puzzles)
        self.total_questions = 5
        self.question_index = 0
        self.correct = 0
        self.mistakes = 0
        self.finished = False
        self.feedback = "这关改成了高难度成语寻踪：根据释义，在大字阵里按相邻路径找出完整成语。"
        self.load_current_question()

    def load_current_question(self):
        current = self.puzzles[self.question_index]
        self.clue = current["clue"]
        self.answer = current["answer"]
        self.answer_chars = list(self.answer)
        self.grid_size = 6
        self.selected_cells = []
        self.grid_rects = []
        self.reset_btn = None
        self.build_grid(current["decoys"])

    def build_grid(self, decoys):
        while True:
            path = self.generate_answer_path()
            if path is None:
                continue

            filler_pool = decoys + self.answer_chars * 2
            self.board = [[random.choice(filler_pool) for _ in range(self.grid_size)] for _ in range(self.grid_size)]
            for idx, (r, c) in enumerate(path):
                self.board[r][c] = self.answer_chars[idx]

            self.answer_path = path
            break

    def generate_answer_path(self):
        directions = [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)]
        for _ in range(200):
            start = (random.randrange(self.grid_size), random.randrange(self.grid_size))
            path = [start]
            used = {start}
            while len(path) < len(self.answer_chars):
                r, c = path[-1]
                candidates = []
                for dr, dc in directions:
                    nr, nc = r + dr, c + dc
                    if 0 <= nr < self.grid_size and 0 <= nc < self.grid_size and (nr, nc) not in used:
                        candidates.append((nr, nc))
                if not candidates:
                    break
                nxt = random.choice(candidates)
                path.append(nxt)
                used.add(nxt)
            if len(path) == len(self.answer_chars):
                return path
        return None

    def is_adjacent(self, a, b):
        return max(abs(a[0] - b[0]), abs(a[1] - b[1])) == 1

    def selected_text(self):
        return "".join(self.board[r][c] for r, c in self.selected_cells)

    def reset_selection(self, message, count_mistake=False):
        self.selected_cells = []
        if count_mistake:
            self.mistakes += 1
        self.feedback = message

    def choose_cell(self, row, col):
        cell = (row, col)
        if cell in self.selected_cells:
            return

        expected_index = len(self.selected_cells)
        chosen_char = self.board[row][col]
        expected_char = self.answer_chars[expected_index]

        if expected_index > 0 and not self.is_adjacent(self.selected_cells[-1], cell):
            self.reset_selection("所选字必须和上一个字相邻，本题当前路径已清空。", count_mistake=True)
            return

        if chosen_char != expected_char:
            self.reset_selection(f"你点到了“{chosen_char}”，但这一位应该不是它，本题当前路径已清空。", count_mistake=True)
            return

        self.selected_cells.append(cell)
        if len(self.selected_cells) == len(self.answer_chars):
            self.correct += 1
            self.question_index += 1
            if self.question_index >= self.total_questions:
                self.finished = True
                self.feedback = f"五道成语寻踪全部完成，最后一个成语是“{self.answer}”。"
            else:
                finished_answer = self.answer
                self.feedback = f"本题找对了：{finished_answer}，继续下一题。"
                self.load_current_question()
        else:
            self.feedback = f"已找到 {len(self.selected_cells)}/{len(self.answer_chars)} 个字。"

    def handle_event(self, event):
        if self.finished:
            return
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            if self.reset_btn and self.reset_btn.collidepoint(event.pos):
                self.reset_selection("本题当前路径已手动清空。")
                return

            for row in range(self.grid_size):
                for col in range(self.grid_size):
                    rect = self.grid_rects[row][col]
                    if rect.collidepoint(event.pos):
                        self.choose_cell(row, col)
                        return

    def draw_grid(self):
        self.grid_rects = []
        start_x = 700
        start_y = 255
        cell = 72
        gap = 8

        for row in range(self.grid_size):
            rect_row = []
            for col in range(self.grid_size):
                rect = pygame.Rect(start_x + col * (cell + gap), start_y + row * (cell + gap), cell, cell)
                rect_row.append(rect)
                selected = (row, col) in self.selected_cells
                round_rect(SCREEN, BLUE if selected else (248, 250, 255), rect, 16, border=2, border_color=BLUE_D if selected else GRAY)
                draw_text(self.board[row][col], FONT_L, (255, 255, 255) if selected else TEXT, rect.centerx, rect.centery, center=True)
            self.grid_rects.append(rect_row)

    def draw(self):
        panel = pygame.Rect(150, 118, WIDTH - 300, HEIGHT - 230)
        round_rect(SCREEN, PANEL, panel, 24)
        draw_text("成语寻踪挑战", FONT_L, TEXT, 190, 155)
        draw_text(f"题目进度：{self.question_index + (0 if self.finished else 1)}/{self.total_questions}", FONT_M, SUB, panel.right - 370, 162)
        draw_text(f"累计失误：{self.mistakes}", FONT_M, SUB, panel.right - 370, 202)

        draw_wrapped_text("规则：根据中文释义，在右侧 6×6 字阵中，按相邻路径依次找出完整成语。可以斜着走，但每一步都必须和上一步相邻；一旦点错字或跳格，本题当前路径就会清空。", FONT_S, DARK, pygame.Rect(190, 220, 420, 92), line_gap=8)

        clue_rect = pygame.Rect(210, 345, 390, 92)
        round_rect(SCREEN, (240, 244, 255), clue_rect, 18)
        draw_wrapped_text(f"线索：{self.clue}" if not self.finished else "五题都完成了。", FONT_M, DARK, clue_rect.inflate(-18, -14), line_gap=8)

        draw_text("当前路径：", FONT_M, SUB, 210, 470)
        path_rect = pygame.Rect(210, 505, 390, 92)
        round_rect(SCREEN, (255, 255, 255), path_rect, 18, border=2, border_color=BLUE)
        current = self.selected_text()
        display = "  ".join(current) if current else "尚未开始"
        draw_wrapped_text(
            display,
            FONT_M if len(display) > 8 else FONT_L if current else FONT_M,
            TEXT if current else SUB,
            path_rect.inflate(-16, -14),
            line_gap=6,
            center=True,
        )

        draw_text(f"目标长度：{len(self.answer_chars)} 字成语", FONT_M, SUB, 210, 615)
        draw_wrapped_text("提示：字阵里可能有重复字，别只看字形，要看路径顺序。", FONT_S, SUB, pygame.Rect(210, 648, 390, 42), line_gap=6)

        self.reset_btn = pygame.Rect(210, 700, 160, 52)
        round_rect(SCREEN, RED, self.reset_btn, 16)
        draw_text("清空当前路径", FONT_S, (255, 255, 255), self.reset_btn.centerx, self.reset_btn.centery, center=True)

        if not self.finished:
            self.draw_grid()
        else:
            draw_text(f"完成 5 题，答对 {self.correct} 题。", FONT_L, GREEN if self.correct == self.total_questions else ORANGE, 970, 430, center=True)
            draw_wrapped_text("这关已经换成新的高难度中文小游戏：不需要输入，只要根据释义在字阵里寻路找成语。", FONT_M, SUB, pygame.Rect(710, 500, 430, 80), center=True)

        draw_wrapped_text(
            self.feedback,
            FONT_S,
            GREEN if "找对了" in self.feedback or self.finished else ORANGE,
            pygame.Rect(210, 758, 420, 44),
            line_gap=4,
        )

    def is_finished(self):
        return self.finished

    def get_score(self):
        base = int(self.correct / self.total_questions * 100)
        return max(30, min(100, base - self.mistakes * 5 + 8))

    def get_message(self):
        return f"完成 {self.correct}/{self.total_questions} 题成语寻踪，累计失误 {self.mistakes} 次"


# ==========================================================
# 游戏8：贪吃蛇冲刺
# ==========================================================
class SnakeGame:
    def __init__(self):
        self.reset()

    def reset(self):
        self.cols = 18
        self.rows = 14
        self.cell = 32
        self.offset_x = 680
        self.offset_y = 235
        self.score_per_food = 10
        self.base_move_delay = 12
        self.min_move_delay = 4
        self.speedup_every_foods = 2
        self.move_delay = self.base_move_delay
        self.attempts = 1
        self.last_score = 0
        self.last_foods_eaten = 0
        self.last_move_count = 0
        self.finished = False
        self.feedback = "方向键或 WASD 控制，先用慢速度稳稳起步。"
        self.start_round(increment=False)

    def start_round(self, increment=True):
        if increment:
            self.attempts += 1
        center_row = self.rows // 2
        center_col = self.cols // 2
        self.snake = [
            (center_row, center_col - 1),
            (center_row, center_col - 2),
            (center_row, center_col - 3),
        ]
        self.direction = (0, 1)
        self.pending_direction = (0, 1)
        self.finished = False
        self.score = 0
        self.foods_eaten = 0
        self.move_count = 0
        self.move_delay = self.base_move_delay
        self.frame_count = 0
        self.spawn_food()

    def spawn_food(self):
        occupied = set(self.snake)
        choices = [(r, c) for r in range(self.rows) for c in range(self.cols) if (r, c) not in occupied]
        self.food = random.choice(choices) if choices else None

    def is_reverse(self, new_direction):
        return new_direction[0] == -self.direction[0] and new_direction[1] == -self.direction[1]

    def handle_event(self, event):
        if event.type != pygame.KEYDOWN:
            return

        if event.key == pygame.K_r:
            if self.finished:
                self.feedback = "你重新开始了一局贪吃蛇，系统会以最后一局结束时的分数结算。"
            else:
                self.feedback = "你手动重开了这一局贪吃蛇。"
            self.start_round(increment=True)
            return

        if self.finished:
            return

        mapping = {
            pygame.K_UP: (-1, 0),
            pygame.K_w: (-1, 0),
            pygame.K_DOWN: (1, 0),
            pygame.K_s: (1, 0),
            pygame.K_LEFT: (0, -1),
            pygame.K_a: (0, -1),
            pygame.K_RIGHT: (0, 1),
            pygame.K_d: (0, 1),
        }
        new_direction = mapping.get(event.key)
        if new_direction and not self.is_reverse(new_direction):
            self.pending_direction = new_direction

    def fail_round(self, message):
        self.finished = True
        self.last_score = self.score
        self.last_foods_eaten = self.foods_eaten
        self.last_move_count = self.move_count
        self.feedback = f"{message} 本局结束，最终得分 {self.last_score} 分。按 R 可以再来一局，系统会以最后一局分数为准。"

    def update(self):
        if self.finished:
            return

        self.frame_count += 1
        if self.frame_count < self.move_delay:
            return
        self.frame_count = 0

        if not self.is_reverse(self.pending_direction):
            self.direction = self.pending_direction

        head_row, head_col = self.snake[0]
        dr, dc = self.direction
        next_head = (head_row + dr, head_col + dc)

        if not (0 <= next_head[0] < self.rows and 0 <= next_head[1] < self.cols):
            self.fail_round("撞墙了，本局从 0 分重新开始。")
            return

        growing = next_head == self.food
        body_to_check = self.snake if growing else self.snake[:-1]
        if next_head in body_to_check:
            self.fail_round("咬到自己了，本局从 0 分重新开始。")
            return

        self.snake.insert(0, next_head)
        self.move_count += 1

        if growing:
            self.score += self.score_per_food
            self.foods_eaten += 1
            self.spawn_food()
            self.move_delay = max(
                self.min_move_delay,
                self.base_move_delay - self.foods_eaten // self.speedup_every_foods,
            )
            self.feedback = (
                f"吃到果子 +{self.score_per_food} 分，身体变长了。"
                f" 目前长度 {len(self.snake)}，速度也比刚开始更快一些。"
            )
        else:
            self.snake.pop()

    def draw_board(self):
        board_rect = pygame.Rect(
            self.offset_x,
            self.offset_y,
            self.cols * self.cell,
            self.rows * self.cell,
        )
        round_rect(SCREEN, (242, 246, 255), board_rect.inflate(24, 24), 24)

        for row in range(self.rows):
            for col in range(self.cols):
                rect = pygame.Rect(
                    self.offset_x + col * self.cell,
                    self.offset_y + row * self.cell,
                    self.cell - 2,
                    self.cell - 2,
                )
                pygame.draw.rect(SCREEN, (235, 240, 248), rect, border_radius=8)

        if self.food is not None:
            food_rect = pygame.Rect(
                self.offset_x + self.food[1] * self.cell + 6,
                self.offset_y + self.food[0] * self.cell + 6,
                self.cell - 14,
                self.cell - 14,
            )
            pygame.draw.ellipse(SCREEN, ORANGE, food_rect)
            pygame.draw.ellipse(SCREEN, (255, 228, 150), food_rect.inflate(-10, -10))
            pygame.draw.line(
                SCREEN,
                GREEN_D,
                (food_rect.centerx, food_rect.top + 2),
                (food_rect.centerx + 4, food_rect.top - 4),
                3,
            )

        for idx, (row, col) in enumerate(self.snake):
            rect = pygame.Rect(
                self.offset_x + col * self.cell + 3,
                self.offset_y + row * self.cell + 3,
                self.cell - 8,
                self.cell - 8,
            )
            color = GREEN_D if idx == 0 else GREEN
            round_rect(SCREEN, color, rect, 10)
            if idx == 0:
                eye_y = rect.top + 10
                pygame.draw.circle(SCREEN, (255, 255, 255), (rect.left + 11, eye_y), 3)
                pygame.draw.circle(SCREEN, (255, 255, 255), (rect.right - 11, eye_y), 3)

    def draw(self):
        panel = pygame.Rect(150, 118, WIDTH - 300, HEIGHT - 230)
        round_rect(SCREEN, PANEL, panel, 24)
        draw_text("贪吃蛇冲刺", FONT_L, TEXT, 190, 155)
        draw_text(f"当前分数：{self.score}", FONT_M, SUB, 190, 215)
        draw_text(f"最后一局：{self.last_score}", FONT_M, SUB, 190, 255)
        draw_text(f"尝试次数：{self.attempts}", FONT_M, SUB, 190, 295)
        draw_text(f"当前长度：{len(self.snake)}", FONT_M, SUB, 190, 335)
        draw_text(f"已吃果子：{self.foods_eaten}", FONT_M, SUB, 190, 375)

        rule_rect = pygame.Rect(190, 420, 420, 165)
        round_rect(SCREEN, (242, 246, 255), rule_rect, 20)
        draw_wrapped_text(
            f"规则：方向键或 WASD 控制方向。每吃 1 个果子加 {self.score_per_food} 分，身体会越来越长；一开始速度更慢，吃得越多速度越快。没有固定通关分数，撞墙或咬到自己时，本局结束，并以最后一局得分结算。按 R 可以随时重开。",
            FONT_S,
            DARK,
            rule_rect.inflate(-24, -20),
            line_gap=8,
        )
        draw_wrapped_text(
            self.feedback,
            FONT_S,
            GREEN if self.finished else ORANGE,
            pygame.Rect(190, 615, 420, 105),
            line_gap=8,
        )
        draw_text(f"当前速度档位：{self.base_move_delay - self.move_delay + 1}", FONT_S, SUB, 190, 742)
        draw_text("小提示：越贪吃，蛇越长，节奏也会越来越快。", FONT_S, SUB, 190, 772)

        self.draw_board()

        if self.finished:
            draw_text(f"本局结束，最后得分 {self.last_score} 分", FONT_L, GREEN, 970, 710, center=True)

    def is_finished(self):
        return self.finished

    def get_score(self):
        return self.last_score

    def get_message(self):
        final_length = 3 + self.last_foods_eaten
        return f"最后一局吃到 {self.last_foods_eaten} 个果子，长度到 {final_length} 格，得分 {self.last_score} 分，共尝试 {self.attempts} 次"


# ==========================================================
# 主应用
# ==========================================================
class App:
    def __init__(self):
        self.levels = [LevelState(name) for name in LEVEL_NAMES]
        self.games = self.build_games()
        self.current_level = 0
        self.scene = "menu"   # menu / play / result
        self.student_name = "学生"
        self.name_input = ""
        self.info = "请输入学生姓名，然后开始闯关。"
        self.text_input_enabled = False
        self.sync_text_input_mode()

    # ------------------------------------------------------
    # 控制逻辑
    # ------------------------------------------------------
    def all_resolved(self):
        return all(level.status in ["cleared", "skipped"] for level in self.levels)

    def total_score(self):
        return sum(level.score for level in self.levels)

    def max_total_score(self):
        return sum(LEVEL_MAX_SCORE)

    def build_games(self):
        return [
            PatternGame(),
            MathGame(),
            MemoryGame(),
            MinesweeperGame(),
            SlidePuzzleGame(),
            SokobanGame(),
            TypingGame(),
            SnakeGame(),
        ]

    def sync_text_input_mode(self):
        if not hasattr(pygame, "key"):
            return

        should_enable = self.scene == "menu"

        if should_enable and not self.text_input_enabled:
            if hasattr(pygame.key, "start_text_input"):
                pygame.key.start_text_input()
            self.text_input_enabled = True
        elif not should_enable and self.text_input_enabled:
            if hasattr(pygame.key, "stop_text_input"):
                pygame.key.stop_text_input()
            self.text_input_enabled = False

    def mark_clear_if_needed(self):
        game = self.games[self.current_level]
        level = self.levels[self.current_level]
        if game.is_finished():
            level.status = "cleared"
            level.score = game.get_score()
            level.best_msg = game.get_message()

    def skip_level(self):
        level = self.levels[self.current_level]
        if level.status == "pending":
            level.status = "skipped"
            level.score = 0
            level.best_msg = "已跳过"
        if self.current_level < len(self.games) - 1:
            self.current_level += 1
        self.sync_text_input_mode()

    def prev_level(self):
        if self.current_level > 0:
            self.current_level -= 1
        self.sync_text_input_mode()

    def next_level(self):
        self.mark_clear_if_needed()
        if self.current_level < len(self.games) - 1:
            self.current_level += 1
        self.sync_text_input_mode()

    def submit(self):
        self.mark_clear_if_needed()
        if self.all_resolved():
            self.scene = "result"
        self.sync_text_input_mode()

    def restart_all(self):
        self.levels = [LevelState(name) for name in LEVEL_NAMES]
        self.games = self.build_games()
        self.current_level = 0
        self.scene = "menu"
        self.info = "请输入学生姓名，然后开始闯关。"
        self.sync_text_input_mode()

    # ------------------------------------------------------
    # 菜单界面
    # ------------------------------------------------------
    def handle_menu(self, event):
        start_btn = Button(WIDTH // 2 - 150, 640, 300, 70, "开始闯关", GREEN, GREEN_D)
        if start_btn.clicked(event):
            if self.name_input.strip():
                self.student_name = self.name_input.strip()
            self.scene = "play"
            self.sync_text_input_mode()
        if event.type == pygame.KEYDOWN:
            if event.key == pygame.K_BACKSPACE:
                self.name_input = self.name_input[:-1]
            elif event.key == pygame.K_RETURN:
                if self.name_input.strip():
                    self.student_name = self.name_input.strip()
                self.scene = "play"
                self.sync_text_input_mode()
        elif event.type == getattr(pygame, "TEXTINPUT", None):
            incoming = getattr(event, "text", "")
            if incoming and len(self.name_input) < 12:
                self.name_input += incoming[: max(0, 12 - len(self.name_input))]

    def draw_menu(self):
        SCREEN.fill(BG)
        card = pygame.Rect(170, 95, WIDTH - 340, HEIGHT - 180)
        round_rect(SCREEN, PANEL, card, 30)
        draw_text("益智闯关乐园", FONT_XL, TEXT, WIDTH // 2, 165, center=True)
        draw_text("欢迎挑战", FONT_M, SUB, WIDTH // 2, 225, center=True)
        draw_wrapped_text(
            "游戏说明：每完成一关会累计积分，可以跳过当前关，也可以回退到上一关。第四关已经改成更轻量的双阶段扫雷，第一张更基础、第二张稍难一点，必须把所有雷都标出来才算通过；第七关是高难度成语寻踪；第八关新增贪吃蛇冲刺，没有固定通关分数，撞到后按最后一局得分结算。",
            FONT_M,
            DARK,
            pygame.Rect(240, 292, card.width - 140, 110),
            line_gap=8,
        )
        draw_text("请输入学生姓名：", FONT_MB, TEXT, WIDTH // 2 - 250, 455)
        input_rect = pygame.Rect(WIDTH // 2 - 40, 440, 360, 62)
        round_rect(SCREEN, (255, 255, 255), input_rect, 16, border=2, border_color=BLUE)
        if hasattr(pygame, "key") and hasattr(pygame.key, "set_text_input_rect"):
            pygame.key.set_text_input_rect(input_rect)
        draw_text(self.name_input or "", FONT_M, TEXT, input_rect.x + 18, input_rect.y + 14)
        if not self.name_input:
            draw_text("例如：张小明", FONT_M, (160, 168, 180), input_rect.x + 18, input_rect.y + 14)
        mouse = pygame.mouse.get_pos()
        Button(WIDTH // 2 - 150, 640, 300, 70, "开始闯关", GREEN, GREEN_D).draw(mouse)
        draw_text("按 Enter 也可以开始", FONT_S, SUB, WIDTH // 2, 728, center=True)

    # ------------------------------------------------------
    # 顶部状态栏 / 底部导航
    # ------------------------------------------------------
    def draw_top_bar(self):
        bar = pygame.Rect(18, 16, WIDTH - 36, 104)
        round_rect(SCREEN, PANEL, bar, 20)
        draw_text(f"学生：{self.student_name}", FONT_MB, TEXT, 36, 34)
        draw_text(f"总积分：{self.total_score()}", FONT_MB, ORANGE, 260, 34)
        draw_text(f"当前关卡：{self.current_level + 1}/{len(self.levels)}", FONT_MB, BLUE, 470, 34)
        draw_wrapped_text(LEVEL_NAMES[self.current_level], FONT_S, DARK, pygame.Rect(36, 62, 560, 28), line_gap=4)

        badge_width = 46
        gap = 10
        total_width = len(self.levels) * badge_width + (len(self.levels) - 1) * gap
        start_x = bar.right - total_width - 28
        for idx, level in enumerate(self.levels):
            x = start_x + idx * (badge_width + gap)
            rect = pygame.Rect(x, 28, badge_width, 28)
            color = GRAY
            if level.status == "cleared":
                color = GREEN
            elif level.status == "skipped":
                color = ORANGE
            round_rect(SCREEN, color, rect, 12)
            draw_text(idx + 1, FONT_TINY, (255, 255, 255) if level.status != "pending" else TEXT, rect.centerx, rect.centery, center=True)

        draw_text("绿=完成  橙=跳过  灰=未处理", FONT_TINY, SUB, start_x, 68)

    def draw_bottom_bar(self):
        mouse = pygame.mouse.get_pos()
        y = HEIGHT - 72
        prev_btn = Button(90, y, 170, 56, "上一关", PURPLE, BLUE)
        skip_btn = Button(290, y, 170, 56, "跳过本关", ORANGE, (240, 150, 40))
        next_btn = Button(WIDTH - 410, y, 170, 56, "下一关", BLUE, BLUE_D)
        submit_btn = Button(WIDTH - 210, y, 150, 56, "提交", GREEN, GREEN_D)

        prev_btn.draw(mouse)
        skip_btn.draw(mouse)
        next_btn.draw(mouse)
        submit_btn.draw(mouse)

        draw_text("完成当前关卡后可直接点“下一关”，全部处理完再点“提交”。", FONT_S, SUB, WIDTH // 2, y + 18, center=True)
        return prev_btn, skip_btn, next_btn, submit_btn

    # ------------------------------------------------------
    # 游戏界面
    # ------------------------------------------------------
    def handle_play(self, event):
        game = self.games[self.current_level]
        game.handle_event(event)

        y = HEIGHT - 72
        prev_btn = Button(90, y, 170, 56, "上一关")
        skip_btn = Button(290, y, 170, 56, "跳过本关")
        next_btn = Button(WIDTH - 410, y, 170, 56, "下一关")
        submit_btn = Button(WIDTH - 210, y, 150, 56, "提交")

        if prev_btn.clicked(event):
            self.prev_level()
        elif skip_btn.clicked(event):
            self.skip_level()
        elif next_btn.clicked(event):
            self.next_level()
        elif submit_btn.clicked(event):
            self.submit()

    def update_play(self):
        game = self.games[self.current_level]
        if hasattr(game, "update"):
            game.update()
        self.mark_clear_if_needed()

    def draw_play(self):
        SCREEN.fill(BG)
        self.draw_top_bar()
        self.games[self.current_level].draw()
        self.draw_bottom_bar()

    # ------------------------------------------------------
    # 结果界面
    # ------------------------------------------------------
    def handle_result(self, event):
        restart_btn = Button(WIDTH // 2 - 185, HEIGHT - 110, 170, 58, "重新开始", BLUE, BLUE_D)
        quit_btn = Button(WIDTH // 2 + 15, HEIGHT - 110, 170, 58, "退出程序", RED, (200, 70, 70))
        if restart_btn.clicked(event):
            self.restart_all()
        elif quit_btn.clicked(event):
            self.sync_text_input_mode()
            pygame.quit()
            sys.exit()

    def draw_result(self):
        SCREEN.fill(BG)
        card = pygame.Rect(110, 50, WIDTH - 220, HEIGHT - 140)
        round_rect(SCREEN, PANEL, card, 28)
        draw_text("闯关结果", FONT_XL, TEXT, WIDTH // 2, 95, center=True)
        draw_text(f"学生：{self.student_name}", FONT_MB, DARK, 150, 150)
        draw_text(f"总积分：{self.total_score()}", FONT_MB, ORANGE, 360, 150)

        headers = ["关卡", "状态", "积分", "说明"]
        xs = [150, 440, 570, 680]
        header_y = 220
        for title, x in zip(headers, xs):
            draw_text(title, FONT_MB, TEXT, x, header_y)
        pygame.draw.line(SCREEN, GRAY, (145, header_y + 38), (WIDTH - 145, header_y + 38), 2)

        y = 282
        row_height = 50
        for level in self.levels:
            status_txt = "已完成" if level.status == "cleared" else "已跳过" if level.status == "skipped" else "未处理"
            status_color = GREEN if level.status == "cleared" else ORANGE if level.status == "skipped" else SUB
            draw_text(level.name, FONT_S, TEXT, 150, y)
            draw_text(status_txt, FONT_S, status_color, 440, y)
            draw_text(level.score, FONT_S, BLUE, 570, y)
            draw_wrapped_text(level.best_msg, FONT_S, SUB, pygame.Rect(680, y - 2, 540, 38), line_gap=4)
            y += row_height

        draw_wrapped_text(
            "说明：只有全部关卡都已完成或已跳过，才能进入最终结果页面。现在的汇总页已经按 8 个关卡重新排版，避免新增玩法后文字和成绩说明互相挤压。",
            FONT_S,
            SUB,
            pygame.Rect(150, HEIGHT - 180, WIDTH - 300, 50),
            line_gap=8,
        )
        mouse = pygame.mouse.get_pos()
        Button(WIDTH // 2 - 185, HEIGHT - 110, 170, 58, "重新开始", BLUE, BLUE_D).draw(mouse)
        Button(WIDTH // 2 + 15, HEIGHT - 110, 170, 58, "退出程序", RED, (200, 70, 70)).draw(mouse)

    # ------------------------------------------------------
    # 主循环
    # ------------------------------------------------------
    def run(self):
        while True:
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    self.sync_text_input_mode()
                    pygame.quit()
                    sys.exit()

                if self.scene == "menu":
                    self.handle_menu(event)
                elif self.scene == "play":
                    self.handle_play(event)
                elif self.scene == "result":
                    self.handle_result(event)

            self.sync_text_input_mode()

            if self.scene == "menu":
                self.draw_menu()
            elif self.scene == "play":
                self.update_play()
                self.draw_play()
            elif self.scene == "result":
                self.draw_result()

            pygame.display.flip()
            CLOCK.tick(FPS)


# ==========================================================
# 主程序入口
# ==========================================================
if __name__ == "__main__":
    App().run()
