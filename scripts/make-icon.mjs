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
