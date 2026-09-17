import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(OPFLateRegister(cameras: cameras));
}

class OPFLateRegister extends StatelessWidget {
  final List<CameraDescription> cameras;
  const OPFLateRegister({super.key, required this.cameras});
  @override Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner:false, title:'OPF Late Register',
    theme:ThemeData(useMaterial3:true, colorSchemeSeed:Colors.teal),
    home:HomePage(cameras:cameras),
  );
}

class HomePage extends StatefulWidget {
  final List<CameraDescription> cameras;
  const HomePage({super.key, required this.cameras});
  @override State<HomePage> createState()=>_HomePageState();
}

class _HomePageState extends State<HomePage> {
  CameraController? controller;
  List<Map<String,dynamic>> students=[];
  List<Map<String,dynamic>> attendance=[];
  String startTime='08:00';
  bool loading=true;
  final name=TextEditingController();
  String className='';
  DateTime selectedDate=DateTime.now();

  @override void initState(){super.initState(); load();}

  Future<void> load() async {
    final p=await SharedPreferences.getInstance();
    students=(jsonDecode(p.getString('students')??'[]') as List).map((e)=>Map<String,dynamic>.from(e)).toList();
    attendance=(jsonDecode(p.getString('attendance')??'[]') as List).map((e)=>Map<String,dynamic>.from(e)).toList();
    startTime=p.getString('start')??'08:00';
    await initCamera();
    if(mounted)setState(()=>loading=false);
  }

  Future<void> initCamera() async {
    if(widget.cameras.isEmpty)return;
    final cam=widget.cameras.firstWhere((c)=>c.lensDirection==CameraLensDirection.back,orElse:()=>widget.cameras.first);
    controller=CameraController(cam,ResolutionPreset.medium,enableAudio:false);
    try{await controller!.initialize();}catch(_){}
    if(mounted)setState((){});
  }

  Future<void> save() async {
    final p=await SharedPreferences.getInstance();
    await p.setString('students',jsonEncode(students));
    await p.setString('attendance',jsonEncode(attendance));
    await p.setString('start',startTime);
  }

  int lateMinutes(DateTime d){
    final x=startTime.split(':');
    final s=DateTime(d.year,d.month,d.day,int.parse(x[0]),int.parse(x[1]));
    return d.difference(s).inMinutes;
  }

  String ds(DateTime d)=>DateFormat('yyyy-MM-dd').format(d);

  Future<void> capture() async {
    if(controller==null || !controller!.value.isInitialized)return;
    final file=await controller!.takePicture();
    if(!mounted)return;
    await showRegisterDialog(file.path);
  }

  Future<void> showRegisterDialog(String photoPath) async {
    name.clear(); className='';
    await showDialog(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('طالب علم رجسٹر کریں',textDirection:TextDirection.rtl),
      content:Directionality(textDirection:TextDirection.rtl,child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:name,decoration:const InputDecoration(labelText:'بچے کا نام')),
        const SizedBox(height:10),
        DropdownButtonFormField<String>(
          value:className.isEmpty?null:className,
          decoration:const InputDecoration(labelText:'کلاس'),
          items:['دوم','سوم','چہارم','پنجم','ششم','ہفتم','ہشتم','نہم','دہم'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),
          onChanged:(v)=>className=v??'',
        )
      ])),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('منسوخ')),
        FilledButton(onPressed:()async{
          if(name.text.trim().isEmpty||className.isEmpty)return;
          final id=DateTime.now().millisecondsSinceEpoch.toString();
          final s={'id':id,'name':name.text.trim(),'className':className,'photo':photoPath};
          students.add(s);
          await addAttendance(s);
          await save();
          if(ctx.mounted)Navigator.pop(ctx);
          setState((){});
        },child:const Text('محفوظ کریں'))
      ],
    ));
  }

  Future<void> addAttendance(Map<String,dynamic> s) async {
    final now=DateTime.now();
    attendance.insert(0,{'id':now.microsecondsSinceEpoch.toString(),'studentId':s['id'],'name':s['name'],'className':s['className'],'date':ds(now),'time':DateFormat('HH:mm').format(now),'lateMin':lateMinutes(now)});
  }

  Future<void> pickDate() async {
    final d=await showDatePicker(context:context,initialDate:selectedDate,firstDate:DateTime(2020),lastDate:DateTime(2100));
    if(d!=null)setState(()=>selectedDate=d);
  }

  Future<void> exportCsv() async {
    final rows=<List<dynamic>>[['تاریخ','نام','کلاس','وقت','تاخیر (منٹ)']];
    for(final e in attendance.where((e)=>e['date']==ds(selectedDate)))rows.add([e['date'],e['name'],e['className'],e['time'],e['lateMin']]);
    final csv=const ListToCsvConverter().convert(rows);
    final dir=await getApplicationDocumentsDirectory();
    final f=File('${dir.path}/late-register-${ds(selectedDate)}.csv');
    await f.writeAsString('\uFEFF$csv');
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('CSV محفوظ ہوگئی: ${f.path}')));
  }

  @override void dispose(){controller?.dispose();name.dispose();super.dispose();}

  @override Widget build(BuildContext context){
    final day=ds(selectedDate);
    final list=attendance.where((e)=>e['date']==day).toList();
    return Scaffold(
      appBar:AppBar(title:const Text('تاخیر سے آنے والوں کا رجسٹر',textDirection:TextDirection.rtl),centerTitle:true),
      body:loading?const Center(child:CircularProgressIndicator()):Directionality(textDirection:TextDirection.rtl,child:ListView(padding:const EdgeInsets.all(14),children:[
        const Text('او پی ایف پبلک سکول',textAlign:TextAlign.center,style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
        const Text('نگران: قاری عبدالماجد',textAlign:TextAlign.center),
        const SizedBox(height:12),
        if(controller!=null&&controller!.value.isInitialized)AspectRatio(aspectRatio:controller!.value.aspectRatio,child:ClipRRect(borderRadius:BorderRadius.circular(14),child:CameraPreview(controller!))),
        const SizedBox(height:10),
        FilledButton.icon(onPressed:capture,icon:const Icon(Icons.camera_alt),label:const Text('تصویر لیں اور طالب علم رجسٹر کریں')),
        const SizedBox(height:18),
        Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
          Row(children:[Expanded(child:Text('رجسٹر: $day',style:const TextStyle(fontWeight:FontWeight.bold))),IconButton(onPressed:pickDate,icon:const Icon(Icons.calendar_month)),IconButton(onPressed:exportCsv,icon:const Icon(Icons.file_download))]),
          if(list.isEmpty)const Padding(padding:EdgeInsets.all(20),child:Text('اس تاریخ کا کوئی ریکارڈ نہیں'))
          else ...list.map((e)=>ListTile(title:Text(e['name']),subtitle:Text('کلاس: ${e['className']}  •  وقت: ${e['time']}'),trailing:Text(e['lateMin']>0?'${e['lateMin']} منٹ لیٹ':'وقت پر',style:TextStyle(color:e['lateMin']>0?Colors.red:Colors.teal,fontWeight:FontWeight.bold))))
        ]))),
        const SizedBox(height:10),
        ExpansionTile(title:Text('ترتیبات اور طلبہ کی فہرست (${students.length})'),children:[
          ListTile(title:const Text('اسکول شروع ہونے کا وقت'),subtitle:Text(startTime),trailing:IconButton(icon:const Icon(Icons.edit),onPressed:()async{final t=await showTimePicker(context:context,initialTime:TimeOfDay(hour:int.parse(startTime.split(':')[0]),minute:int.parse(startTime.split(':')[1])));if(t!=null){setState(()=>startTime='${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}');save();}})),
          ...students.map((s)=>ListTile(title:Text(s['name']),subtitle:Text('کلاس: ${s['className']}'),trailing:IconButton(icon:const Icon(Icons.delete_outline),onPressed:()async{students.removeWhere((x)=>x['id']==s['id']);await save();setState((){});})))
        ])
      ]))
    );
  }
}
