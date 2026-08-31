{
  Генетический алгоритм: отбор, кроссовер, мутация, адаптация параметров
  и ведение истории прогона.

  Модуль не зависит от GraphABC — эволюцию можно прогонять без окна.
}
unit DP_Evolution;

uses DP_Config, DP_World, DP_Bot;

var
  generationNumber: integer := 0;
  ///Средняя и максимальная приспособленность последнего поколения
  currentAverageFitness: real := 0;
  currentMaximumFitness: integer := 0;
  ///История для графика, индекс 0 — самое свежее поколение
  generationDurations: array of real;
  averageFitnessHistory: array of real;
  ///Сколько элементов истории реально заполнено. Без этого первые сто
  ///поколений считаются вместе с нулями-заполнителями, которые сбивают
  ///и масштаб графика, и подписи под ним.
  historyFilled: integer := 0;

  ///Текущие параметры среды и мутации
  currentMutationRate: real := BASE_MUTATION_RATE;
  currentAppleCount: integer := INITIAL_APPLES;
  currentWallCount: integer := INITIAL_WALLS;

  generationStartTime: integer;

  ///Средняя приспособленность за предыдущее окно наблюдения
  previousWindowAverage: real := 0;
  windowFitnessSum: real := 0;
  windowGenerations: integer := 0;
  stagnationCounter: integer := 0;

  logFile: Text;
  isLogOpen: boolean := False;

procedure AddGenerationDuration(newDuration: real);
begin
  for var index := High(generationDurations) downto 1 do
    generationDurations[index] := generationDurations[index - 1];
  generationDurations[0] := newDuration;
end;

procedure AddAverageFitness(newFitness: real);
begin
  for var index := High(averageFitnessHistory) downto 1 do
    averageFitnessHistory[index] := averageFitnessHistory[index - 1];
  averageFitnessHistory[0] := newFitness;
  if historyFilled < HISTORY_LENGTH then
    Inc(historyFilled);
end;

procedure LogGeneration(durationMs: real);
begin
  if not isLogOpen then exit;
  Writeln(logFile,
    generationNumber, ';',
    currentAverageFitness.ToString('F2'), ';',
    currentMaximumFitness, ';',
    currentMutationRate.ToString('F4'), ';',
    currentAppleCount, ';',
    currentWallCount, ';',
    Round(durationMs));
  Flush(logFile);
end;

procedure CloseLog;
begin
  if isLogOpen then
  begin
    Close(logFile);
    isLogOpen := False;
  end;
end;

/// Рулетка: вероятность выбрать бота пропорциональна его приспособленности.
/// Единица добавляется, чтобы бот с нулём очков тоже имел шанс.
/// Раньше этот код был написан дважды, и во второй копии сумма затиралась
/// присваиванием вместо накопления — вторым родителем почти всегда
/// оказывался один и тот же бот.
function SelectParent(survivors: array of integer; totalFitness: integer): integer;
begin
  Result := survivors[0];
  var threshold := Random(totalFitness);
  var sum := 0;
  for var index := 0 to High(survivors) do
  begin
    sum += bots[survivors[index]].fitness + 1;
    if sum >= threshold then
    begin
      Result := survivors[index];
      exit;
    end;
  end;
end;

/// Двухточечный кроссовер: средний участок генома меняется местами
procedure Crossover(parent1, parent2: GenomeArray; var child1, child2: GenomeArray);
begin
  var point1 := Random(GENOME_LENGTH - 1) + 1;
  var point2 := Random(GENOME_LENGTH - point1) + point1;
  for var gene := 0 to GENOME_LENGTH - 1 do
    if (gene < point1) or (gene >= point2) then
    begin
      child1[gene] := parent1[gene];
      child2[gene] := parent2[gene];
    end
    else
    begin
      child1[gene] := parent2[gene];
      child2[gene] := parent1[gene];
    end;
end;

procedure Mutate(var genome: GenomeArray);
begin
  for var gene := 0 to GENOME_LENGTH - 1 do
    if Random < currentMutationRate then
      genome[gene] := Random(GENOME_LENGTH);
end;

/// Пересматривает вероятность мутации и сложность среды по среднему за окно.
///
/// Раньше это делалось каждое поколение, и контур управления реагировал на
/// собственные действия: добавление десяти стен роняло среднюю
/// приспособленность, падение засчитывалось как стагнация и поднимало
/// мутацию, хотя популяция не деградировала — просто усложнилась задача.
procedure AdaptParameters;
begin
  windowFitnessSum += currentAverageFitness;
  Inc(windowGenerations);
  if windowGenerations < ENVIRONMENT_ADAPT_INTERVAL then exit;

  var windowAverage := windowFitnessSum / windowGenerations;
  var improved := windowAverage > previousWindowAverage;
  // Отличаем плато от настоящей деградации. Без этого получается
  // положительная обратная связь: мутация растёт на стагнации, высокая
  // мутация разрушает найденные геномы, падение снова засчитывается как
  // стагнация — и вероятность мутации уезжает в потолок, откуда популяция
  // уже не выбирается.
  var degraded := windowAverage < previousWindowAverage * DEGRADATION_RATIO;
  previousWindowAverage := windowAverage;

  if windowAverage > FITNESS_THRESHOLD then
  begin
    // Популяция освоила текущий уровень. Усложняем среду только когда рост
    // прекратился: если наращивать сложность, пока обучение ещё идёт, она
    // обгоняет популяцию и приспособленность обваливается.
    if not improved then
    begin
      if currentAppleCount > MINIMUM_APPLES then currentAppleCount -= 1;
      if currentWallCount < MAXIMUM_WALLS then currentWallCount += 10;
    end;
    stagnationCounter := 0;
    if currentMutationRate > BASE_MUTATION_RATE then
      currentMutationRate := Max(currentMutationRate - MUTATION_DECREMENT, BASE_MUTATION_RATE);
  end
  else
  begin
    // Ниже порога сложность не растёт. Затяжное отсутствие роста лечим
    // мутацией, а если популяция совсем не справляется — упрощаем среду.
    if improved or degraded then
    begin
      // Рост — значит текущая настройка работает; падение — значит
      // предыдущее повышение мутации навредило. В обоих случаях мутацию
      // снижаем, а счётчик стагнации сбрасываем.
      stagnationCounter := 0;
      if currentMutationRate > BASE_MUTATION_RATE then
        currentMutationRate := Max(currentMutationRate - MUTATION_DECREMENT, BASE_MUTATION_RATE);
    end
    else
    begin
      stagnationCounter += 1;
      if stagnationCounter >= STAGNATION_THRESHOLD then
        currentMutationRate := Min(
          BASE_MUTATION_RATE + (stagnationCounter - STAGNATION_THRESHOLD + 1) * MUTATION_INCREMENT,
          MAXIMUM_MUTATION_RATE);
    end;

    if windowAverage < FITNESS_THRESHOLD / 2 then
    begin
      if currentAppleCount < INITIAL_APPLES then currentAppleCount += 1;
      if currentWallCount > INITIAL_WALLS then currentWallCount -= 10;
    end;
  end;

  windowFitnessSum := 0;
  windowGenerations := 0;
end;

/// Строит геномы следующего поколения: элита переносится без изменений,
/// остальные получаются кроссовером двух родителей с последующей мутацией.
procedure CreateNewPopulation;
var
  survivors: array of integer;
  ///Хранятся только геномы: запись Bot весит около килобайта из-за visited
  newGenomes: array[0..MAXIMUM_BOTS - 1] of GenomeArray;
  eliteIndices: array[0..ELITE_BOT_COUNT - 1] of integer;
begin
  currentAverageFitness := 0;
  currentMaximumFitness := bots[0].fitness;
  for var botIndex := 0 to MAXIMUM_BOTS - 1 do
  begin
    currentAverageFitness += bots[botIndex].fitness;
    if bots[botIndex].fitness > currentMaximumFitness then
      currentMaximumFitness := bots[botIndex].fitness;
  end;
  currentAverageFitness /= MAXIMUM_BOTS;

  AddAverageFitness(currentAverageFitness);
  AdaptParameters;

  SetLength(survivors, MAXIMUM_BOTS);
  for var index := 0 to MAXIMUM_BOTS - 1 do
    survivors[index] := index;

  // Элита: лучшие геномы переносятся в новое поколение без изменений
  var eliteCount := 0;
  while (eliteCount < ELITE_BOT_COUNT) and (Length(survivors) > 0) do
  begin
    var best := 0;
    for var index := 1 to High(survivors) do
      if bots[survivors[index]].fitness > bots[survivors[best]].fitness then
        best := index;
    eliteIndices[eliteCount] := survivors[best];
    newGenomes[eliteCount] := bots[survivors[best]].genome;
    Inc(eliteCount);
    survivors[best] := survivors[High(survivors)];
    SetLength(survivors, Length(survivors) - 1);
  end;

  var totalFitness := 0;
  for var index := 0 to High(survivors) do
    totalFitness += bots[survivors[index]].fitness + 1;
  if totalFitness < 1 then totalFitness := 1;

  var filled := eliteCount;
  while filled < MAXIMUM_BOTS do
  begin
    var parent1, parent2: integer;
    if Length(survivors) > 0 then
    begin
      parent1 := SelectParent(survivors, totalFitness);
      parent2 := SelectParent(survivors, totalFitness);
    end
    else
    begin
      parent1 := eliteIndices[Random(eliteCount)];
      parent2 := eliteIndices[Random(eliteCount)];
    end;

    var child1, child2: GenomeArray;
    Crossover(bots[parent1].genome, bots[parent2].genome, child1, child2);
    Mutate(child1);
    Mutate(child2);

    newGenomes[filled] := child1;
    Inc(filled);
    if filled < MAXIMUM_BOTS then
    begin
      newGenomes[filled] := child2;
      Inc(filled);
    end;
  end;

  for var botIndex := 0 to MAXIMUM_BOTS - 1 do
    bots[botIndex].genome := newGenomes[botIndex];
end;

/// Новая карта и сброс состояния всех ботов. Раскладка одна на поколение,
/// иначе приспособленности, снятые в разных средах, несравнимы.
procedure StartGeneration;
begin
  var layout := GenerateField(currentWallCount, currentAppleCount, POISON_COUNT);
  var direction := Random(4);
  for var botIndex := 0 to MAXIMUM_BOTS - 1 do
    ResetBotState(bots[botIndex], layout.startX, layout.startY, direction);
  activeBotCount := MAXIMUM_BOTS;
end;

procedure AdvanceGeneration;
begin
  CreateNewPopulation;
  StartGeneration;
  Inc(generationNumber);
  var duration := Milliseconds - generationStartTime;
  AddGenerationDuration(duration);
  generationStartTime := Milliseconds;
  LogGeneration(duration);
end;

/// Один такт симуляции для всей популяции.
/// Возвращает True, если поколение сменилось.
function SimulationStep: boolean;
begin
  Result := false;
  UpdateWorld;
  for var botIndex := 0 to MAXIMUM_BOTS - 1 do
  begin
    RunBotTick(botIndex);
    if activeBotCount <= 0 then
    begin
      AdvanceGeneration;
      Result := true;
      exit;
    end;
  end;
end;

procedure InitializeEvolution;
begin
  // Фиксированное зерно делает прогон воспроизводимым: два запуска дают
  // одинаковый журнал, и интересный прогон можно повторить.
  if RANDOM_SEED <> 0 then
    Randomize(RANDOM_SEED)
  else
    Randomize;

  SetLength(generationDurations, HISTORY_LENGTH);
  SetLength(averageFitnessHistory, HISTORY_LENGTH);
  for var index := 0 to HISTORY_LENGTH - 1 do
  begin
    generationDurations[index] := 0;
    averageFitnessHistory[index] := 0;
  end;

  try
    Assign(logFile, LOG_FILE_NAME);
    Rewrite(logFile);
    Writeln(logFile, 'generation;avg_fitness;max_fitness;mutation_rate;apples;walls;duration_ms');
    isLogOpen := True;
  except
    // Журнал не критичен: если файл занят, симуляция идёт без него
    isLogOpen := False;
  end;

  for var botIndex := 0 to MAXIMUM_BOTS - 1 do
    RandomizeGenome(bots[botIndex]);
  StartGeneration;
  generationStartTime := Milliseconds;
end;

begin
end.
