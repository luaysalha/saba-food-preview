const CATALOG_URL='https://wbmstvclrdxcakiwufwn.supabase.co';
const CATALOG_KEY='sb_publishable_T8-joxOmHusp0FcQcVzhCQ_9KTM2x8j';
async function catalogRequest(path,options={},token){const r=await fetch(CATALOG_URL+path,{...options,headers:{apikey:CATALOG_KEY,...(token?{Authorization:'Bearer '+token}:{}),...options.headers}});const text=await r.text();let data;try{data=JSON.parse(text)}catch{data=text}if(!r.ok)throw new Error(data.message||data.msg||data.error_description||'Begäran misslyckades ('+r.status+')');return data}
