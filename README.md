# mongodberl
通过poolboy使用 [erlmongo mongo client](https://github.com/yunba/erlmongo) 来支持mongo replica set特性

提供两个接口供外部程序使用  
1、start_link  
   调用poolboy建立线程池  
2、get_value_from_mongo  
  通过mongoapi:findOne/3查询数据 

    
