"""Render the installer artwork. Native icons remain Finder items, not baked pixels."""
from PIL import Image, ImageDraw, ImageFont
from pathlib import Path
root=Path(__file__).resolve().parents[2]
out=root/'assets/dmg';out.mkdir(parents=True,exist_ok=True)
for scale,name in [(1,'background.png'),(2,'background@2x.png')]:
 im=Image.new('RGB',(760*scale,460*scale),'#f7f6f2');d=ImageDraw.Draw(im)
 def font(size):return ImageFont.truetype('/System/Library/Fonts/SFNS.ttf',size*scale)
 def text(x,y,s,size,color):d.text((x*scale,y*scale),s,font=font(size),fill=color)
 def line(points,color,width):d.line([(int(x*scale),int(y*scale)) for x,y in points],fill=color,width=width*scale)
 text(52,38,'Paper Reader',34,'#222d37')
 text(54,85,'A little space for your next insight.',15,'#67727b')
 # A quiet page-fold motif, with generous empty space around the real icons.
 line([(675,40),(709,40),(709,74)],'#507999',2)
 line([(366,242),(394,242)],'#6b8ba4',2)
 line([(386,234),(394,242),(386,250)],'#6b8ba4',2)
 text(160,356,'Drag Paper Reader into Applications to install.',15,'#4a5965')
 text(54,420,'PDF  /  MARKDOWN  /  AI',10,'#83909a')
 text(579,420,'Made for macOS.',10,'#83909a')
 im.save(out/name,dpi=(72*scale,72*scale))
