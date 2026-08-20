Программа создана для автоматизированного сканирования системных компоненов, обнаруживания лицензий и всей необходимой информации.

### Способ развёртывания:
Качаем файлы PSChecker.ps1 и PSChecker.bat, кладём их в одну папку и запускаем .bat файл от имени администратора
Программа спросит - хотим ли мы устанавливать лицензии на Винду и Офис, после реакции пользователя просканирует всё, что должна сканировать

Текущий список сканирования:
MS Windows
MS Office
BIOS
CPU (Процессор)
GPU (VRAM, Видеокарта)
RAM (ОЗУ, Оперативка)
Disks
List of installed programs (Now it scans all programs, connected to registry | Пока что сканирует всё, что подвязано к реестру. В дальнейшем планируется введение более широкого функционала с привлечением системных вызовов на ЯП низкого уровня)

Задачи на будущее:
- [ ] Сканирование Windows и Office отдельно от установки лицензий
- [ ] Сортировка сканируемых программ
- [ ] Поиск программ по определённым названиям и параметрам
- [ ] Глубокий поиск лицензий на ПО
- [ ] Вшитый MAS, который не надо будет скачивать

A lot of time ago it were planned as windows and office activator which will be used by user but at once i understood that this is not enough and now there is multifunctional script which scans system, creates logs and installs licenses on Windows and Office
