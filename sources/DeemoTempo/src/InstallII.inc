template<class F> bool hookAt(Hook hook,D::Entry e,F replacement,F &original){
    hook(fn<void*>(e),reinterpret_cast<void*>(replacement),reinterpret_cast<void**>(&original));
    return original!=nullptr;
}
bool installAll(const mach_header_64 *header,const char *path){
    if(header->magic!=MH_MAGIC_64 || header->cputype!=CPU_TYPE_ARM64)return false;
    const char *p=reinterpret_cast<const char*>(header+1);
    bool match=false;
    for(unsigned i=0;i<header->ncmds;++i){
        auto c=reinterpret_cast<const load_command*>(p);
        if(c->cmd==LC_UUID)match=!memcmp(reinterpret_cast<const uuid_command*>(p)->uuid,D::uuid,16);
        p+=c->cmdsize;
    }
    if(!match){statusText=@"DEEMO II 构建不匹配";return false;}
    base=reinterpret_cast<uintptr_t>(header);
    for(auto e:D::entries)if(*fn<const uint32_t*>(e)!=e.word){statusText=@"DEEMO II 版本校验失败";return false;}
    void *runtime=dlopen(path,RTLD_LAZY|RTLD_NOLOAD);
    if(!runtime)return false;
    retainObject=(decltype(retainObject))dlsym(runtime,"il2cpp_gchandle_new");
    heldObject=(decltype(heldObject))dlsym(runtime,"il2cpp_gchandle_get_target");
    dropObject=(decltype(dropObject))dlsym(runtime,"il2cpp_gchandle_free");
    newObject=(decltype(newObject))dlsym(runtime,"il2cpp_object_new");
    findField=(decltype(findField))dlsym(runtime,"il2cpp_class_get_field_from_name");
    fieldOffset=(decltype(fieldOffset))dlsym(runtime,"il2cpp_field_get_offset");
    Hook hook=(Hook)dlsym(RTLD_DEFAULT,"MSHookFunction");
    if(!hook){void *lib=dlopen("/var/jb/usr/lib/libsubstrate.dylib",RTLD_LAZY);if(lib)hook=(Hook)dlsym(lib,"MSHookFunction");}
    if(!hook || !retainObject || !heldObject || !dropObject || !newObject || !findField || !fieldOffset){
        statusText=@"DEEMO II 运行接口不可用";return false;
    }
    ready=hookAt(hook,D::settle,settle,originalSettle)
       && hookAt(hook,D::resultInit,initScore,originalResultInit)
       && hookAt(hook,D::addJudge,addJudge,originalAdd)
       && hookAt(hook,D::judge,judge,originalJudge)
       && hookAt(hook,D::spawn,spawn,originalSpawn)
       && hookAt(hook,D::sound,sound,originalSound)
       && hookAt(hook,D::syncAudio,syncAudio,originalSync)
       && hookAt(hook,D::syncChart,alignAudio,originalAlign)
       && hookAt(hook,D::pauseMusic,originalPause,originalPauseMusic)
       && hookAt(hook,D::resumeMusic,originalResume,originalResumeMusic)
       && hookAt(hook,D::release,release,originalRelease)
       && hookAt(hook,D::retry,retry,originalRetry)
       && hookAt(hook,D::loadPlane,initPlane,originalInitPlane)
       && hookAt(hook,D::frame,frame,originalFrame);
    statusText=ready?@"开曲前选择练习倍率":@"DEEMO II 适配未就绪";
    return ready;
}
