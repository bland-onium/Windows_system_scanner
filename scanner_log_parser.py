import codecs
import csv
import os
import re

#
#   USAGE
#   put it into folder with parsable data
#python3 scanner_log_parser.py
#   and it automatically will scan .txt and .log files on signatures of scanner
#   Finally it will create .csv table with data


#   КАК ПОЛЬЗОВАТЬСЯ
#   Кладёшь скрипт в папку, в которой лежат записи сканера
#python3 scanner_log_parser.py
#   Он сам всё проверит и сообщит когда всё закончено
#   В конце выдаст .csv таблицу с данными



def walk(home):
    try:
        entries = os.listdir(home)
    except PermissionError:
        return

    for entry in entries:
        fullpath = os.path.join(home, entry)

        if os.path.isdir(fullpath):
            yield from walk(fullpath)
        elif os.path.isfile(fullpath):
            yield fullpath
    return


def parse_programms_table(lines):

	# Находим строку заголовка с нужными колонками
	header_idx = next(
		(i for i, line in enumerate(lines)
		 if "Program" in line and "Version" in line and "Serial" in line),
		None,
	)
	if header_idx is None:
		return []

	header = lines[header_idx]

	# Определяем границы колонок по позициям заголовков
	columns = ["Program", "Version", "Serial / ProdID"]
	all_cols = ["Program", "Version", "Manufacturer",
				"Installation Date", "Update Date", "Serial / ProdID"]

	spans = []
	for col in columns:
		start = header.index(col)
		ends = [header.index(c) for c in all_cols if header.index(c) > start]
		end = min(ends) if ends else len(header)
		spans.append((start, end))

	result = []
	for line in lines[header_idx + 1:]:
		if "ViPNeT" in line:
			break
		stripped = line.replace(" ", "")
		if not stripped or set(stripped) <= {"-", "="}:
			continue  # пропускаем пустые строки и строки-разделители
		row = [line[start:end].strip() for start, end in spans]
		if any(row):
			result.append(row)

	return result

def parse_programms_table_two(lines):
    columns = ["Program", "Version", "Serial / ProdID"]

    # 1. Находим строку заголовка (достаточно Program + Version)
    header_idx = next(
        (i for i, line in enumerate(lines)
         if "Program" in line and "Version" in line),
        None,
    )
    if header_idx is None:
        return []

    header = lines[header_idx]

    # 2. Все возможные колонки в порядке их появления в шапке
    all_cols = ["Program", "Version", "Manufacturer",
                "Installation Date", "Update Date", "Serial / ProdID"]

    # Оставляем только те, что реально есть в шапке, и сортируем по позиции
    present = []
    for c in all_cols:
        idx = header.find(c)
        if idx != -1:
            present.append((idx, c))
    present.sort()

    # 3. Для каждой нужной колонки определяем span
    spans = []
    for col in columns:
        idx = header.find(col)
        if idx == -1:
            spans.append((None, None))  # колонки нет
            continue
        # конец — начало следующей присутствующей колонки правее
        ends = [pos for pos, _ in present if pos > idx]
        end = min(ends) if ends else len(header)
        spans.append((idx, end))

    # 4. Парсим строки данных
    result = []
    for line in lines[header_idx + 1:]:
        if "ViPNeT" in line:
            break
        stripped = line.replace(" ", "")
        if not stripped or set(stripped) <= {"-", "="}:
            continue
        row = []
        for start, end in spans:
            if start is None:
                row.append(None)
            else:
                row.append(line[start:end].strip() or None)
        if any(row):
            for i in range(len(row)):
                if row[i] == None:
                    row[i] = "Unknown"
            result.append(row)

    return result

def parse_programs_list(text):
    """
    Парсит данные о программах из текста.
    
    Args:
        text: Входной текст для парсинга
        stop_word: Специальное слово, при встрече которого парсинг прекращается
    
    Returns:
        list: Список словарей с ключами "Program", "Version", "Serial / ProdID"
    """
    columns = ["Program", "Version", "Installation Date"]
    results = []
    
    # Разделяем текст на блоки (по пустым строкам)
    #blocks = re.split(r'\n\s*\n', text.strip())
    
    program = None; version = None; serial = None
    for block in text:
        print("Block:",block)
        if not block.strip():
            continue
            
        # Проверяем на наличие стоп-слова
        if "ViPNeT" in block:
            break
        
        # Извлекаем Program
        program_match = re.search(r'^Program\s*:\s*(.+)$', block, re.MULTILINE)
        if program_match:
            program = program_match.group(1).strip()
        
        # Извлекаем Version
        version_match = re.search(r'^Version\s*:\s*(.+)$', block, re.MULTILINE)
        if version_match:
            version = version_match.group(1).strip()
        
        # Извлекаем Serial / ProdID (в данном формате отсутствует, 
        # но может быть в других вариантах)
        serial_match = re.search(r'^(?:Serial|ProdID|Serial / ProdID|Installation Date)\s*:\s*(.+)$', 
            block, re.MULTILINE)
        if serial_match:
            serial = serial_match.group(1).strip() if serial_match else None

        print(" prog:",program," ver:",version," ser:",serial)
        if block.startswith("Manufacturer"):
            results.append([
                program if program else "Unknown",
                version if version else "Unknown",
                serial  if serial  else "Unknown"
            ])
            program = None; version = None; serial = None
    if program and version and serial:
        results.append([ 
            program, 
            version if version else "Unknown", 
            serial if serial else "Unknown"
            ])
    
    return results


# ---------------------------------------------------------------------------
# Новый блок: надёжный посекционный парсер
# ---------------------------------------------------------------------------

def read_text(file):
    """Читает файл с fallback-кодировками.

    Важно: часть логов пишется в UTF-16 (дефолт Out-File в PowerShell 5.1).
    Такой файл декодируется utf-8/cp1251 «молча» (NUL-байты валидны), и все
    regex потом не срабатывают — поэтому UTF-16 детектим в первую очередь.
    """
    with open(file, "rb") as f:
        raw = f.read()
    if raw.startswith((codecs.BOM_UTF16_LE, codecs.BOM_UTF16_BE)):
        return raw.decode("utf-16")
    sample = raw[:400]
    if sample and sample.count(b"\x00") > len(sample) // 4:
        try:
            return raw.decode("utf-16")
        except UnicodeDecodeError:
            pass
    for enc in ("utf-8", "cp1251"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", errors="replace")


def split_sections(lines):
    """Разбивает лог на секции по заголовкам '=== TITLE ==='.

    Не полагается на порядок/количество секций — каждая ищется по имени.
    """
    sections = []
    title = None
    buf = []
    for line in lines:
        s = line.strip()
        # Заголовок секции: строка, начинающаяся с '==='.
        # Важно: в логах встречаются НЕзакрытые заголовки вида
        # '=== VIPNET SEEKING MODULE STARTED', поэтому закрывающие '===' не требуем.
        if s.startswith("===") and len(s) > 6:
            inner = s.strip("=").strip()
            if inner:
                if title is not None:
                    sections.append((title, buf))
                title = inner
                buf = []
            continue
        if title is not None:
            buf.append(line)
    if title is not None:
        sections.append((title, buf))
    return sections


def find_section(sections, *keywords):
    """Возвращает строки первой секции, в заголовке которой есть все keywords."""
    for title, lines in sections:
        t = title.lower()
        if all(k in t for k in keywords):
            return lines
    return []


def kv_collect(lines, patterns):
    """Собирает значения по ключам 'Key : value' с повторами (несколько устройств).

    patterns: список кортежей (имя_колонки, скомпилированный regex с группой (.*))
    """
    out = {k: [] for k, _ in patterns}
    for line in lines:
        if ":" not in line:
            continue
        s = line.strip()
        for key, rx in patterns:
            m = rx.match(s)
            if m:
                out[key].append(m.group(1).strip())
                break
    return out


def col(values):
    """Склеивает список значений в одну ячейку."""
    return "\n".join(values)


def get_activation(lines, keyword):
    """Ищет строку '[GOOD] ...' / '[BAD] ...' с keyword (Windows/Office)."""
    for line in lines:
        m = re.match(r"^\[(?:GOOD|BAD)\]\s*(.+)$", line.strip())
        if m and keyword.lower() in m.group(1).lower():
            return m.group(1).strip()
    return ""


def parse_vipnet(lines):
    """Парсит секцию ViPNet: либо пары 'Имя/Тип поставщика', либо список CSP
    вида 'Microsoft ... Provider' + '1 - PROV_RSA_FULL'."""
    names, types, fullname, creatime, lastwrite = [], [], [], [], []
    if any("поставщика" in l.lower() for l in lines):
        for l in lines:
            s = l.strip()
            m = re.match(r"^Имя поставщика\s*:\s*(.*)$", s)
            if m:
                names.append(m.group(1).strip())
            m = re.match(r"^Тип поставщика\s*:\s*(.*)$", s)
            if m:
                types.append(m.group(1).strip())
            m = re.match(r"^FullName\s*:\s*(.*)$", s)
            if m:
                fullname.append(m.group(1).strip())
            m = re.match(r"^CreationTime\s*:\s*(.*)$", s)
            if m:
                creatime.append(m.group(1).strip())
            m = re.match(r"^LastWriteTime\s*:\s*(.*)$", s)
            if m:
                lastwrite.append(m.group(1).strip())
    else:
        for l in lines:
            s = l.strip()
            if not s or s.startswith("*") or ":" in s:
                continue
            if s.upper().startswith(("FINISH", "END")):
                continue
            if set(s) <= {"-", "="}:
                continue
            if re.match(r"^\d+\s*-\s*\S+", s):
                types.append(s)
            else:
                names.append(s)
    return names, types, fullname, creatime, lastwrite


def parse(file):
    text = read_text(file)
    lines = text.splitlines()
    sections = split_sections(lines)
    print("We came into device scanning")
    # --- Имя ПК: из шапки транскрипта -> из 'RUN SCANNER ON PC' -> из BIOS ---
    pc_name = "Unknown"
    m = re.search(r"Компьютер:\s*([^\s(]+)", text)
    if not m:
        m = re.search(r"RUN SCANNER ON PC:\s*(\S+)", text)
    if m:
        pc_name = m.group(1)

    # --- Активация Windows / Office (секция, иначе глобальный поиск) ---
    windows = get_activation(find_section(sections, "windows", "activation"), "windows") \
        or get_activation(lines, "windows")
    office = get_activation(find_section(sections, "office", "licens"), "office") \
        or get_activation(find_section(sections, "office", "activation"), "office") \
        or get_activation(lines, "office")

    # --- Сеть ---
    ip_lines = find_section(sections, "ip", "adress") or find_section(sections, "ip", "address")
    net = kv_collect(ip_lines, [
        ("adapter", re.compile(r"^Network\s+Adapter\s*:\s*(.*)$", re.I)),
        ("ip1", re.compile(r"^IP\s*Adress\(es\)\s*:\s*(.*)$", re.I)),
        ("ip2", re.compile(r"^IP\s*Address\(es\)\s*:\s*(.*)$", re.I)),
        ("ip3", re.compile(r"^IPv?4?\s*Address\(es\)?\s*:\s*(.*)$", re.I)),
    ])
    adapters = [v for v in net["adapter"] if v]
    ipvals = [v for v in (net["ip1"] + net["ip2"] + net["ip3"]) if v]
    # Fallback: если имя адаптера в IP-секции пустое/отсутствует (сбой WMI и т.п.),
    # берём его из секции 'Getting data about network adapters'
    # (предпочитаем включённые адаптеры, иначе первый в списке).
    if not adapters:
        na_lines = find_section(sections, "network", "adapters") \
            or find_section(sections, "data", "network")
        na = kv_collect(na_lines, [
            ("name", re.compile(r"^Name\s*:\s*(.*)$")),
            ("enabled", re.compile(r"^NetEnabled\s*:\s*(.*)$")),
        ])
        picked = []
        for i, n in enumerate(na["name"]):
            e = na["enabled"][i].strip().lower() if i < len(na["enabled"]) else ""
            if e == "true":
                picked.append(n)
        adapters = picked or na["name"][:1]

    # --- CPU ---
    cpu = kv_collect(find_section(sections, "data", "cpu"), [
        ("id", re.compile(r"^ProcessorID\s*:\s*(.*)$")),
        ("name", re.compile(r"^Name\s*:\s*(.*)$")),
    ])

    # --- GPU ---
    gpu = kv_collect(find_section(sections, "data", "gpu"), [
        ("name", re.compile(r"^Name\s*:\s*(.*)$")),
        ("mem", re.compile(r"^Memory\s*:\s*(.*)$")),
        ("mem2", re.compile(r"^AdapterRAM\s*:\s*(.*)$")),
    ])
    if not gpu["mem"]:
        gpu["mem"] = gpu["mem2"]

    # --- RAM ---
    ram = kv_collect(find_section(sections, "data", "ram"), [
        ("vendor", re.compile(r"^Vendor\s*:\s*(.*)$")),
        ("part", re.compile(r"^PartNumber\s*:\s*(.*)$")),
        ("size", re.compile(r"^Size\s*\(\s*(?:Gb|GB)\s*\)\s*:\s*(.*)$")),
    ])

    # --- Диски (только Model и Size (GB); FreeSpace и прочее игнорируется,
    #     чтобы размеры не разъезжались относительно моделей) ---
    disks = kv_collect(find_section(sections, "data", "disk"), [
        ("model", re.compile(r"^Model\s*:\s*(.*)$")),
        ("size", re.compile(r"^Size\s*\(\s*GB\s*\)\s*:\s*(.*)$")),
    ])

    # --- BIOS ---
    bios = kv_collect(find_section(sections, "data", "bios"), [
        ("pc", re.compile(r"^ComputerName\s*:\s*(.*)$")),
        ("name", re.compile(r"^Name\s*:\s*(.*)$")),
        ("serial", re.compile(r"^SerialNumber\s*:\s*(.*)$")),
    ])
    if pc_name == "Unknown" and bios["pc"]:
        pc_name = bios["pc"][0]

    # --- Монитор ---
    mon = kv_collect(find_section(sections, "data", "monitor"), [
        ("serial", re.compile(r"^Serial\s*N(?:umber)?\s*:\s*(.*)$")),
        ("model", re.compile(r"^Model\s*:\s*(.*)$")),
    ])

    # --- Установленные программы ---
    sys_lines = find_section(sections, "system", "scanner")
    if not sys_lines and "Program" in text:
        sys_lines = lines
    prog_rows = parse_programms_table(sys_lines) if sys_lines else []
    if prog_rows == []:
        prog_rows = parse_programs_list(sys_lines)
    if prog_rows == []:
        prog_rows = parse_programms_table_two(sys_lines)
    prog_names, prog_versions, prog_serials = [], [], []
    print("\nsys_lines\n", sys_lines)
    print("\nprogrows\n", prog_rows)
    for r in prog_rows:
        for k in range(len(r)):   
            if k == 0:
                prog_names.append(r[0])
            if k == 1:
                prog_versions.append(r[1])
            if k == 2:
                prog_serials.append(r[2])
    r = 0
    while r < len(prog_names):
#    for r in range(len(prog_names)):
        if prog_names[r] == prog_versions[r] == prog_serials[r]:
            print("All are equal")
            prog_names.pop(r)
            prog_versions.pop(r)
            prog_serials.pop(r)
            r -= 1
        else:
            r += 1
    print("\n")
    print("Prog names:", prog_names)
    print(prog_versions)
    print(prog_serials)
    print("\n")
        #r = (list(r) + ["", "", ""])[:3]
        #prog_names.append(r[0])
        #prog_versions.append(r[1])
        #prog_serials.append(r[2])

    # --- ViPNet ---
    vip_names, vip_types, vip_full, vip_create, vip_write = parse_vipnet(find_section(sections, "vipnet"))

    parts = file.split("/")
    file_short = "/" + "/".join(parts[-2:])

    # --- Фиксированный порядок колонок (29 шт., как в шапке) ---
    row = [
        pc_name,
        windows,
        office,
        file_short,
        col(adapters),
        col(ipvals),
        col(cpu["id"]),
        col(cpu["name"]),
        col(gpu["mem"]),
        col(gpu["name"]),
        col(ram["part"]),
        col(ram["size"]),
        col(ram["vendor"]),
        col(disks["model"]),
        col(disks["size"]),
        col(bios["pc"]),
        col(bios["name"]),
        col(bios["serial"]),
        col(mon["serial"]),
        col(mon["model"]),
        col(prog_names),
        col(prog_versions),
        col(prog_serials),
        col(vip_names),
        col(vip_types),
        col(vip_full),
        col(vip_create),
        col(vip_write),
        "", "", "", "",
    ]
    return row[:29]


def return_home(home):
    base = os.path.basename(os.path.normpath(home))
    return os.path.join(home, base + "_analysed.csv")


def write(file, row, headerOne, headerTwo):
    file_exists = os.path.isfile(file)
    with open(file, mode="a", encoding="utf-8-sig", newline="") as f:
        writer = csv.writer(f)

        if not file_exists:
            writer.writerow(headerOne)
            writer.writerow(headerTwo)
        writer.writerow(row)
    return


def main():
    home = os.getcwd()

    header_one = [
        "PC name", "Windows activation", "Office activation",
        "Home folder",
        "Network", "",
        "CPU", "",
        "GPU", "",
        "RAM", "", "",
        "Disks", "",
        "BIOS", "", "",
        "Monitor", "",
        "Installed programs", "", "",
        "Safety", "", "", "", "", "", ]
    header_two = [
        "Имя ПК", "Активация Windows", "Активация Office",
        "Папка хранения",
        "Адаптер сети", "IP Адрес",
        "ID Процессора", "Имя",
        "Размер (МБ)", "Имя",
        "Серийный номер", "Размер (ГБ)", "Производитель",
        "Модель", "Размер (ГБ)",
        "Имя ПК", "Версия BIOS", "Серийный номер",
        "Серийный номер", "Модель",
        "Программа", "Версия", "Серийный номер",

        "Поставщик", "Имя программного обеспечения",
        "Имя драйвера", "Последнее обновление", "Дата установки"
    ]

    outfile = return_home(home)
    for file in walk(home):
        low = file.lower()
        if not (low.endswith(".txt") or low.endswith(".log")):
            continue
        if file.endswith("_analysed.csv"):
            continue
        print("Exploring file: ", file)
        data = parse(file)
        '''
        try:
            data = parse(file)
        except Exception as e:
            print(f"  ERROR while parsing {file}:")# {e}")
            break
            continue
        #'''
        if not data:
            continue
        write(outfile, data, header_one, header_two)

    print("Done. Result is written to:", outfile)
    return


main()
