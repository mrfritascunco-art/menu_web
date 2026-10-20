/* Sesión compartida de Mr. Fritas Gestión. No almacena contraseñas. */
window.MFSession={
  save(auth,remember=true){
    if(!auth?.access_token||!auth?.refresh_token)return;
    const key="mf_gestion_session";
    const store=remember?localStorage:sessionStorage;
    (remember?sessionStorage:localStorage).removeItem(key);
    store.setItem(key,JSON.stringify({access_token:auth.access_token,refresh_token:auth.refresh_token,expires_at:Date.now()+Number(auth.expires_in||3600)*1000,email:auth.user?.email||""}));
  },
  async get(role){
    const key="mf_gestion_session";
    let store=localStorage.getItem(key)?localStorage:sessionStorage;
    let raw=store.getItem(key);
    if(!raw)return null;
    let session;
    try{session=JSON.parse(raw)}catch(e){store.removeItem(key);return null}
    if(!session.access_token||!session.refresh_token)return null;
    const url="https://oiybkvtamrhjfcyfayes.supabase.co";
    const apiKey="sb_publishable_mGfgsfOujYYOBE0y6YZJ0g_jvAjdWVT";
    if(Number(session.expires_at||0)<Date.now()+90000){
      const response=await fetch(url+"/auth/v1/token?grant_type=refresh_token",{method:"POST",headers:{"apikey":apiKey,"Content-Type":"application/json"},body:JSON.stringify({refresh_token:session.refresh_token})});
      if(!response.ok){store.removeItem(key);return null}
      const refreshed=await response.json();
      session={...session,access_token:refreshed.access_token,refresh_token:refreshed.refresh_token,expires_at:Date.now()+Number(refreshed.expires_in||3600)*1000,email:refreshed.user?.email||session.email};
      store.setItem(key,JSON.stringify(session));
    }
    const check=async name=>{
      const response=await fetch(url+"/rest/v1/rpc/has_staff_role",{method:"POST",headers:{"apikey":apiKey,"Authorization":"Bearer "+session.access_token,"Content-Type":"application/json"},body:JSON.stringify({p_role:name})});
      return response.ok&&(await response.json())===true;
    };
    if(!(await check(role))&&!(role!=="admin"&&await check("admin")))return null;
    return session.access_token;
  },
  async allowed(token,role){
    if(!token)return false;
    const url="https://oiybkvtamrhjfcyfayes.supabase.co";
    const key="sb_publishable_mGfgsfOujYYOBE0y6YZJ0g_jvAjdWVT";
    const check=async name=>{
      const r=await fetch(url+"/rest/v1/rpc/has_staff_role",{method:"POST",headers:{"apikey":key,"Authorization":"Bearer "+token,"Content-Type":"application/json"},body:JSON.stringify({p_role:name}),cache:"no-store"});
      return r.ok&&(await r.json())===true;
    };
    return await check(role)||(role!=="admin"&&await check("admin"));
  },
  watch(role,getToken,onDenied){
    let busy=false;
    const verify=async()=>{
      if(busy||!getToken())return;
      busy=true;
      try{if(!await this.allowed(getToken(),role))onDenied()}catch(e){onDenied()}finally{busy=false}
    };
    const interval=setInterval(verify,20000);
    document.addEventListener("visibilitychange",()=>{if(!document.hidden)verify()});
    window.addEventListener("storage",e=>{if(e.key==="mf_gestion_session"&&!e.newValue)onDenied()});
    return interval;
  },
  clear(){localStorage.removeItem("mf_gestion_session");sessionStorage.removeItem("mf_gestion_session");["mf_kitchen_token","mf_cash_token","mf_admin_token"].forEach(k=>sessionStorage.removeItem(k))}
};

/* Barra común de navegación entre módulos, respetando permisos del personal. */
(function(){
 const pages=[["🍳 Cocina","cocina.html","cocina"],["💵 Caja","caja.html","caja"],["⚙️ Administración","admin-promociones.html","admin"],["👥 Trabajadores","admin-trabajadores.html","admin"]];
 const current=location.pathname.split("/").pop();
 if(!pages.some(p=>p[1]===current))return;
 const style=document.createElement("style");
 style.textContent="#mfGestionNav[hidden]{display:none}#mfGestionNav{position:sticky;top:0;z-index:9999;background:#171717;padding:9px 8px;display:flex;gap:7px;overflow-x:auto;box-shadow:0 3px 12px #0003;scrollbar-width:thin}#mfGestionNav a{flex:1 0 auto;text-align:center;color:#fff;text-decoration:none;font:800 12px Arial,sans-serif;border:1px solid #555;border-radius:10px;padding:11px 8px;white-space:nowrap}#mfGestionNav a.active{background:#ffc400;color:#111;border-color:#ffc400}";
 document.head.appendChild(style);
 const nav=document.createElement("nav");nav.id="mfGestionNav";nav.setAttribute("aria-label","Navegación de Mr Fritas Gestión");nav.hidden=true;
 document.body.insertBefore(nav,document.body.firstChild);
 async function update(){
  try{
   const token=await MFSession.get("cocina")||await MFSession.get("caja")||await MFSession.get("admin");
   if(!token){nav.hidden=true;return}
   const [admin,cocina,caja]=await Promise.all(["admin","cocina","caja"].map(role=>MFSession.allowed(token,role)));
   nav.innerHTML=pages.filter(p=>admin||(p[2]==="cocina"&&cocina)||(p[2]==="caja"&&caja)).map(p=>'<a href="'+p[1]+'"'+(p[1]===current?' class="active" aria-current="page"':'')+'>'+p[0]+'</a>').join("");
   nav.hidden=!nav.children.length;
  }catch(e){nav.hidden=true}
 }
 update();
 document.addEventListener("visibilitychange",()=>{if(!document.hidden)update()});
 window.addEventListener("storage",e=>{if(e.key==="mf_gestion_session")update()});
})();
