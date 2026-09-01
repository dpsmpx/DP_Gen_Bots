{
  Текстовые примитивы поверх картинки: подписи и рамки.
  Единственный модуль, который знает, как выглядит служебный текст.
}
unit DP_Interface;

uses GraphABC;

const
  FONT_SIZE_SMALL  = 9;
  FONT_SIZE_MEDIUM = 14;

/// Текст в рамке с полупрозрачной подложкой
procedure DrawRectangledText(startX, startY, width, height: integer; text: string);
begin
  var savedBrush := Brush.Color;
  var savedPen := Pen.Color;
  var savedFont := Font.Color;

  Pen.Color := clCyan;
  Brush.Color := ARGB(128, 0, 0, 0);
  Rectangle(startX, startY, startX + width, startY + height);
  Font.Color := clWhite;
  DrawTextCentered(startX, startY, startX + width, startY + height, text);

  Brush.Color := savedBrush;
  Pen.Color := savedPen;
  Font.Color := savedFont;
end;

/// Текст в строке, отцентрованный по точке (X, Y).
/// Подложка рисуется заданным цветом; прежняя версия принимала цвет
/// параметром, но не использовала его, а имя параметра перекрывало тип Color.
procedure FillTextInLine(x, y: integer; text: string; backgroundColor: Color; fontSize: integer);
begin
  var savedFontSize := Font.Size;
  var savedBrush := Brush.Color;

  SetFontSize(fontSize);
  // Запас в два символа, чтобы текст не упирался в края подложки
  var halfWidth := TextWidth(text + 'WW') div 2;
  var halfHeight := TextHeight(text) div 2;

  Brush.Color := backgroundColor;
  FillRect(x - halfWidth, y - halfHeight, x + halfWidth, y + halfHeight);
  DrawTextCentered(x - halfWidth, y - halfHeight, x + halfWidth, y + halfHeight, text);

  SetFontSize(savedFontSize);
  Brush.Color := savedBrush;
end;

begin
end.
