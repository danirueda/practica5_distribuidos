# PRÁCTICA 5
**Autor:** Daniel Rueda

Sistema de almacenamiento tolerante a fallos mediante replicación (Primario/Copia).

A tener cuenta las siguientes consideraciones a corregir:

* No hay que mandar latidos si no te mandan mensajes, hay que crear un proceso a parte que mande latidos cada cierto tiempo.
* Para evitar la repetición de operaciones, no basta con guardarse la última operación hecha sino que hay que guardarse un número de secuencia, porque puede suceder que el cliente quiera realizar la misma operación varias veces.
* No hacer todo en una función con muchas líneas de código y hacerlo en funciones mas pequeñas.
* Para quitar los warnings que salen, cambiar el código teniendo en cuenta [esto](http://elixir-lang.org/blog/2016/06/21/elixir-v1-3-0-released/).
