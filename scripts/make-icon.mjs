import sharp from 'sharp';
const pixels=[
'      aa   aa      ',
'     agga agga     ',
'     awka awka     ',
'    agggggggga     ',
'   agggggggggga    ',
'   agllgggllgga    ',
'    aglllllgga     ',
'  aagggggggggaa    ',
' agggglllllgggga   ',
'  aagggggggggaa    ',
'    aaa   aaa      ',
];
const palette={a:'#193b39',g:'#7da96a',l:'#c5d79a',w:'#f8ebcc',k:'#173435'};
let svg='<svg xmlns="http://www.w3.org/2000/svg" width="19" height="19" viewBox="0 0 19 19"><rect width="19" height="19" rx="4" fill="#102b32"/>';
pixels.forEach((row,y)=>[...row].forEach((c,x)=>{if(palette[c])svg+=`<rect x="${x}" y="${y+4}" width="1" height="1" fill="${palette[c]}"/>`;}));svg+='</svg>';
const buf=Buffer.from(svg);
await sharp(buf).resize(193,193,{kernel:'nearest'}).png().toFile('web/favicon.png');
const {readdirSync,readFileSync,existsSync}=await import('node:fs');
for(const [dpi,size] of Object.entries({'mdpi':48,'hdpi':72,'xhdpi':96,'xxhdpi':144,'xxxhdpi':192})) {
 const file=`android/app/src/main/res/mipmap-${dpi}/ic_launcher.png`;
 if(existsSync(file))await sharp(buf).resize(size,size,{kernel:'nearest'}).png().toFile(file);
}
const dir='ios/Runner/Assets.xcassets/AppIcon.appiconset';
if(existsSync(`${dir}/Contents.json`)) {
 const {images}=JSON.parse(readFileSync(`${dir}/Contents.json`,'utf8'));
 for(const icon of images) if(icon.filename){const size=Math.round(parseFloat(icon.size)*parseFloat(icon.scale));await sharp(buf).resize(size,size,{kernel:'nearest'}).png().toFile(`${dir}/${icon.filename}`);}
}
