unit DP_Interface;
uses GraphABC;

var
  FontSizeMedium := 14;

/// Выводит текст в линию (масштабирует по ширине)
procedure FillTextInLine(X, Y: Integer; Text: String; Color: Color; FontSize: integer);
var LastFontSize := Font.Size;
begin
  SetFontSize(FontSize);
  var X1 := X - TextWidth(Text+'WW') div 2;
  var Y1 := Y - TextHeight(Text) div 2;
  var X2 := X + TextWidth(Text+'WW') div 2;
  var Y2 := Y + TextHeight(Text) div 2;
  Brush.Color := ARGB(200, 200, 200, 200);
  FillRect(X1, Y1, X2, Y2);
  DrawTextCentered(X1, Y1, X2, Y2, Text);
  SetFontSize(LastFontSize);
end;

begin
  
end.
