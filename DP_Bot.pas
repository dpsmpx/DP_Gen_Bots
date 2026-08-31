{
  Бот и его виртуальная машина.

  Геном — массив генов 0..GENOME_LENGTH-1. Ген играет две роли сразу:
  команда определяется как остаток от деления на COMMAND_COUNT, а само
  значение служит смещением относительного перехода. Поэтому мутация
  одного гена осмысленна в обеих ролях, а фрагменты генома остаются
  работоспособными после кроссовера.

  Команды:
    0  идти вперёд      пусто — шаг, яблоко — съесть, яд — гибель, стена — стоять
    1  повернуть вправо
    2  повернуть влево
    3  уничтожить яд перед собой
    4  сенсор: ситуация выбирает элемент таблицы переходов в следующих
       SENSOR_SITUATIONS генах, переход относительный
    5  безусловный относительный переход на смещение из следующего гена

  Модуль не зависит от GraphABC.
}
unit DP_Bot;

uses DP_Config, DP_World;

type
  ///Геном как самостоятельный тип: новое поколение хранит только геномы,
  ///а не записи Bot целиком (в каждой лежит массив visited на 900 элементов).
  GenomeArray = array[0..GENOME_LENGTH - 1] of byte;

  Bot = record
    active: boolean;
    x, y: integer;
    ///0 — вверх, далее по часовой стрелке
    direction: integer;
    genomePosition: integer;
    genome: GenomeArray;
    actionCount: integer;
    fitness: integer;
    visited: array[0..FIELD_WIDTH - 1, 0..FIELD_HEIGHT - 1] of boolean;
  end;

var
  bots: array[0..MAXIMUM_BOTS - 1] of Bot;
  ///Сколько ботов ещё живо в текущем поколении
  activeBotCount: integer := MAXIMUM_BOTS;

/// Заполняет геном случайными значениями на весь диапазон.
/// Досылать недостающие команды не нужно: при декодировании по остатку
/// любая команда достижима из любого значения гена.
procedure RandomizeGenome(var bot: Bot);
begin
  for var gene := 0 to GENOME_LENGTH - 1 do
    bot.genome[gene] := Random(GENOME_LENGTH);
end;

/// Готовит бота к новому прогону, сохраняя геном
procedure ResetBotState(var bot: Bot; startX, startY, direction: integer);
begin
  bot.active := true;
  bot.x := startX;
  bot.y := startY;
  bot.direction := direction;
  bot.genomePosition := 0;
  bot.actionCount := 0;
  bot.fitness := 0;
  for var x := 0 to FIELD_WIDTH - 1 do
    for var y := 0 to FIELD_HEIGHT - 1 do
      bot.visited[x, y] := false;
end;

/// Снимает бота с поля. Счётчик живых уменьшается ровно один раз:
/// повторный вызов для уже погибшего бота ничего не делает.
procedure KillBot(botIndex: integer);
begin
  if not bots[botIndex].active then exit;
  bots[botIndex].active := false;
  botFields[botIndex, bots[botIndex].x, bots[botIndex].y] := Empty;
  Dec(activeBotCount);
end;

/// Ситуация, которую различает сенсор команды 4
function SenseSituation(botIndex: integer): integer;
begin
  // Обращение идёт по полям массива, а не через локальную копию записи:
  // Bot содержит массив visited на 900 элементов и копируется целиком.
  var x := bots[botIndex].x;
  var y := bots[botIndex].y;
  var direction := bots[botIndex].direction;
  var front := GetFrontPosition(x, y, direction);
  var left := GetFrontPosition(x, y, (direction - 1 + 4) mod 4);
  var right := GetFrontPosition(x, y, (direction + 1) mod 4);

  if botFields[botIndex, front.x, front.y] = Apple then
    Result := 0
  else if botFields[botIndex, front.x, front.y] = Poison then
    Result := 1
  else if botFields[botIndex, front.x, front.y] = Wall then
    Result := 2
  else if botFields[botIndex, left.x, left.y] = Apple then
    Result := 3
  else if botFields[botIndex, right.x, right.y] = Apple then
    Result := 4
  else
    Result := 5;
end;

/// Номер команды, стоящей под текущей позицией генома
function CurrentCommand(botIndex: integer): integer
  := bots[botIndex].genome[bots[botIndex].genomePosition] mod COMMAND_COUNT;

procedure ExecuteCommand(botIndex: integer);
begin
  if bots[botIndex].actionCount >= MAXIMUM_ACTIONS then
  begin
    KillBot(botIndex);
    exit;
  end;

  case CurrentCommand(botIndex) of
    0:
      begin
        var front := GetFrontPosition(bots[botIndex].x, bots[botIndex].y, bots[botIndex].direction);
        case botFields[botIndex, front.x, front.y] of
          Empty, Apple:
            begin
              var wasApple := botFields[botIndex, front.x, front.y] = Apple;
              botFields[botIndex, bots[botIndex].x, bots[botIndex].y] := Empty;
              bots[botIndex].x := front.x;
              bots[botIndex].y := front.y;
              botFields[botIndex, front.x, front.y] := BotCell;
              if wasApple then
              begin
                bots[botIndex].fitness += FITNESS_APPLE;
                botAppleCount[botIndex] -= 1;
                PlaceApple(botIndex);
              end;
              if not bots[botIndex].visited[front.x, front.y] then
              begin
                bots[botIndex].visited[front.x, front.y] := true;
                bots[botIndex].fitness += FITNESS_NEW_CELL;
              end;
            end;
          Poison:
            begin
              // Наступить на яд смертельно. Прежде эта ветка посимвольно
              // совпадала с Empty: яд молча стирался, штрафа не было, да ещё
              // и начислялся плюс за новую клетку. В модели не оставалось ни
              // одного отрицательного стимула, а сенсор яда был бесполезен.
              botFields[botIndex, bots[botIndex].x, bots[botIndex].y] := Empty;
              bots[botIndex].x := front.x;
              bots[botIndex].y := front.y;
              bots[botIndex].actionCount += 1;
              KillBot(botIndex);
              exit;
            end;
          // Wall и BotCell: бот остаётся на месте
        end;
        bots[botIndex].genomePosition := (bots[botIndex].genomePosition + 1) mod GENOME_LENGTH;
      end;
    1:
      begin
        // Награды за поворот здесь быть не должно. Пока она была, геном из
        // одних поворотов набирал полный лимит очков, ничего не делая и
        // ничем не рискуя, и вытеснял из элиты любую осмысленную стратегию.
        bots[botIndex].direction := (bots[botIndex].direction + 1) mod 4;
        bots[botIndex].genomePosition := (bots[botIndex].genomePosition + 1) mod GENOME_LENGTH;
      end;
    2:
      begin
        bots[botIndex].direction := (bots[botIndex].direction - 1 + 4) mod 4;
        bots[botIndex].genomePosition := (bots[botIndex].genomePosition + 1) mod GENOME_LENGTH;
      end;
    3:
      begin
        var front := GetFrontPosition(bots[botIndex].x, bots[botIndex].y, bots[botIndex].direction);
        if botFields[botIndex, front.x, front.y] = Poison then
        begin
          botFields[botIndex, front.x, front.y] := Empty;
          bots[botIndex].fitness += FITNESS_KILL_POISON;
          PlaceApple(botIndex);
        end;
        bots[botIndex].genomePosition := (bots[botIndex].genomePosition + 1) mod GENOME_LENGTH;
      end;
    4:
      begin
        // Ситуация выбирает элемент таблицы переходов, лежащей в следующих
        // SENSOR_SITUATIONS генах. Прежде переход шёл на абсолютный адрес
        // 0..3, поэтому всё ветвление упиралось в первые клетки генома, а
        // ветки "яблоко впереди" и "ничего не найдено" были неразличимы.
        var situation := SenseSituation(botIndex);
        var offset := bots[botIndex].genome[(bots[botIndex].genomePosition + 1 + situation) mod GENOME_LENGTH];
        bots[botIndex].genomePosition := (bots[botIndex].genomePosition + offset) mod GENOME_LENGTH;
      end;
    5:
      begin
        // Безусловный относительный переход. Прежде адрес брался как
        // genome[...] mod GENOME_LENGTH, но гены хранили только 0..5,
        // поэтому попасть можно было лишь в первые шесть клеток генома.
        var offset := bots[botIndex].genome[(bots[botIndex].genomePosition + 1) mod GENOME_LENGTH];
        bots[botIndex].genomePosition := (bots[botIndex].genomePosition + offset) mod GENOME_LENGTH;
      end;
  end;

  bots[botIndex].actionCount += 1;
end;

/// Один такт бота: служебные команды выполняются до первой команды
/// движения, но не больше MAXIMUM_THINK_TIME штук. Гибель обрывает такт.
procedure RunBotTick(botIndex: integer);
begin
  if not bots[botIndex].active then exit;
  var remaining := MAXIMUM_THINK_TIME - 1;
  while (remaining > 0) and bots[botIndex].active and (CurrentCommand(botIndex) <> 0) do
  begin
    ExecuteCommand(botIndex);
    remaining -= 1;
  end;
  if bots[botIndex].active then
    ExecuteCommand(botIndex);
end;

begin
end.
